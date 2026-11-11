"""Offline, trusted-operator reporting pilot. No mailbox, SQL, AI or signing API."""
import argparse
import csv
import hashlib
import io
import json
import re
import sqlite3
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path


class ReportError(ValueError):
    pass


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
                      allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", value):
        raise ReportError("invalid identifier")
    return value


def iso_date(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise ReportError("date must be YYYY-MM-DD")
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise ReportError("invalid date") from exc


def validate_template(template):
    if not isinstance(template, dict):
        raise ReportError("template must be an object")
    for field in ("id", "version", "source"):
        identifier(template.get(field))
    columns = template.get("columns")
    if not isinstance(columns, list) or not 1 <= len(columns) <= 100:
        raise ReportError("1..100 columns required")
    headers = []
    for column in columns:
        if not isinstance(column, dict):
            raise ReportError("invalid column")
        header = column.get("header")
        if not isinstance(header, str) or not header.strip() or len(header) > 120:
            raise ReportError("invalid header")
        headers.append(header)
        if column.get("operation") not in ("count", "sum"):
            raise ReportError("only count and decimal sum are supported")
        if column["operation"] == "sum":
            identifier(column.get("field"))
    if len(headers) != len(set(headers)):
        raise ReportError("duplicate headers")


class Engine:
    """Caller identities must come from a future authenticated service, not HTTP input.

    The local DB is trusted operator state; tenant filters are defense in depth,
    not a replacement for OS isolation, authenticated roles or encryption.
    """
    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript('''
          CREATE TABLE IF NOT EXISTS templates (
            tenant TEXT, id TEXT, version TEXT, body TEXT, approved_by TEXT,
            PRIMARY KEY(tenant,id,version));
          CREATE TABLE IF NOT EXISTS runs (
            id TEXT PRIMARY KEY, tenant TEXT, body TEXT, status TEXT,
            approved_by TEXT, created_at TEXT);
        ''')

    def close(self):
        self.db.close()

    def approve_template(self, tenant, template, actor):
        identifier(tenant)
        identifier(actor)
        validate_template(template)
        body = canonical(template)
        with self.db:
            old = self.db.execute("SELECT body FROM templates WHERE tenant=? AND id=? AND version=?",
                                  (tenant, template['id'], template['version'])).fetchone()
            if old and old['body'] != body:
                raise ReportError("template version is immutable; use a new version")
            if not old:
                self.db.execute("INSERT INTO templates VALUES (?,?,?,?,?)",
                                (tenant, template['id'], template['version'], body, actor))

    def generate(self, tenant, template_id, version, start, end, records):
        """Dates are inclusive. Importer must supply one explicit authoritative source."""
        identifier(tenant)
        first, last = iso_date(start), iso_date(end)
        if first > last:
            raise ReportError("reversed reporting period")
        template_row = self.db.execute("SELECT * FROM templates WHERE tenant=? AND id=? AND version=?",
                                       (tenant, template_id, version)).fetchone()
        if not template_row:
            raise ReportError("approved template not found for tenant")
        template = json.loads(template_row['body'])
        selected_refs, selected_hashes, seen = [], [], set()
        sums = {column['field']: Decimal(0) for column in template['columns']
                if column['operation'] == 'sum'}
        selected_count = input_count = 0
        for record in records:
            input_count += 1
            if input_count > 100000:
                raise ReportError("record count exceeds 100000")
            if not isinstance(record, dict) or record.get('tenant_id') != tenant:
                raise ReportError("tenant mismatch")
            if record.get('source') != template['source']:
                raise ReportError("unexpected source")
            rid = identifier(record.get('id'))
            if rid in seen:
                raise ReportError("duplicate source record")
            seen.add(rid)
            when = iso_date(record.get('date'))
            if first <= when <= last:
                selected_count += 1
                selected_refs.append({'source': record['source'], 'id': rid, 'date': record['date']})
                selected_hashes.append(digest(record))
                for field in sums:
                    raw = record.get(field)
                    # Decimal strings avoid float rounding and ambiguous separators.
                    if not isinstance(raw, str) or not re.fullmatch(r"-?\d{1,16}(\.\d{1,6})?", raw):
                        raise ReportError("missing or invalid decimal field: " + field)
                    try:
                        sums[field] += Decimal(raw)
                    except InvalidOperation as exc:
                        raise ReportError("invalid decimal") from exc
        values = []
        for column in template['columns']:
            if column['operation'] == 'count':
                values.append(str(selected_count))
                continue
            values.append(format(sums[column['field']], 'f'))
        selected_refs.sort(key=lambda record: record['id'])
        selected_hashes.sort()
        body = {
            'tenant_id': tenant, 'template': template,
            'template_approved_by': template_row['approved_by'],
            'period': {'start': start, 'end': end, 'bounds': 'inclusive'},
            'values': values, 'record_count': selected_count,
            # Keep source transactions in their owning system; persist references only.
            'source_records': selected_refs,
            'source_sha256': digest(selected_hashes),
            'source_reference_sha256': digest(selected_refs),
            'warnings': [] if selected_count else ['No matching records; confirm completeness'],
        }
        run_id = digest(body)
        with self.db:
            self.db.execute("INSERT OR IGNORE INTO runs VALUES (?,?,?,?,?,?)",
                            (run_id, tenant, canonical(body), 'draft', None,
                             datetime.now(timezone.utc).isoformat()))
        return run_id

    def get(self, tenant, run_id):
        row = self.db.execute("SELECT * FROM runs WHERE tenant=? AND id=?", (tenant, run_id)).fetchone()
        if not row:
            raise ReportError("report not found for tenant")
        body = json.loads(row['body'])
        if digest(body) != row['id'] or digest(body['source_records']) != body['source_reference_sha256']:
            raise ReportError("report integrity mismatch")
        return {'id': row['id'], 'status': row['status'], 'approved_by': row['approved_by'],
                'created_at': row['created_at'], 'report': body}

    def approve(self, tenant, run_id, actor, confirmed_count):
        identifier(actor)
        result = self.get(tenant, run_id)
        if type(confirmed_count) is not int or confirmed_count != result['report']['record_count']:
            raise ReportError("operator reconciliation count does not match")
        with self.db:
            # First approval remains attributable; repeating cannot change the approver.
            self.db.execute("UPDATE runs SET status='approved', approved_by=? WHERE tenant=? AND id=? AND status='draft'",
                            (actor, tenant, run_id))

    def export_csv(self, tenant, run_id):
        result = self.get(tenant, run_id)
        if result['status'] != 'approved':
            raise ReportError("report requires approval before export")
        report = result['report']
        stream = io.StringIO(newline='')
        writer = csv.writer(stream)
        # Treat spreadsheet formula prefixes as text, including after whitespace.
        def safe(text):
            return "'" + text if text.lstrip().startswith(('=', '+', '-', '@')) else text
        writer.writerow([safe(c['header']) for c in report['template']['columns']])
        writer.writerow(report['values'])  # values are engine-generated numeric strings
        return stream.getvalue()


def read_json(path):
    with Path(path).open('rb') as stream:
        raw = stream.read(16 * 1024 * 1024 + 1)
    if len(raw) > 16 * 1024 * 1024:
        raise ReportError("input exceeds 16 MiB")
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ReportError("duplicate JSON key")
            result[key] = value
        return result
    def invalid(_):
        raise ReportError("nonfinite JSON value")
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid)


def read_records(path):
    """Stream bounded NDJSON records; don't parse a whole report into RAM."""
    source = Path(path)
    if source.stat().st_size > 16 * 1024 * 1024:
        raise ReportError("records file exceeds 16 MiB")
    count = 0
    with source.open('rb') as stream:
        for line_number, raw in enumerate(stream, 1):
            if len(raw) > 1024 * 1024:
                raise ReportError("record line exceeds 1 MiB")
            if not raw.strip():
                continue
            count += 1
            if count > 100000:
                raise ReportError("record count exceeds 100000")
            record = read_json_line(raw, line_number)
            if not isinstance(record, dict):
                raise ReportError("each NDJSON line must contain one object")
            yield record


def read_json_line(raw, line_number):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ReportError("duplicate JSON key on record line " + str(line_number))
            result[key] = value
        return result
    def invalid(_):
        raise ReportError("nonfinite JSON value on record line " + str(line_number))
    try:
        return json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid)
    except json.JSONDecodeError as exc:
        raise ReportError("invalid JSON on record line " + str(line_number)) from exc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', required=True, help='Private operator-owned SQLite path')
    parser.add_argument('--tenant', required=True)
    sub = parser.add_subparsers(dest='command', required=True)
    t = sub.add_parser('approve-template')
    t.add_argument('--file', required=True)
    t.add_argument('--actor', required=True)
    g = sub.add_parser('generate')
    for arg in ('template', 'version', 'start', 'end', 'records'):
        g.add_argument('--' + arg, required=True)
    for name in ('show', 'approve', 'export'):
        child = sub.add_parser(name)
        child.add_argument('--run', required=True)
        if name == 'approve':
            child.add_argument('--actor', required=True)
            child.add_argument('--confirmed-count', type=int, required=True)
    args = parser.parse_args()
    engine = Engine(args.db)
    try:
        if args.command == 'approve-template':
            engine.approve_template(args.tenant, read_json(args.file), args.actor)
            print('Template approved for offline pilot')
        elif args.command == 'generate':
            print(engine.generate(args.tenant, args.template, args.version, args.start,
                                  args.end, read_records(args.records)))
        elif args.command == 'approve':
            engine.approve(args.tenant, args.run, args.actor, args.confirmed_count)
            print('Approved; not signed or submitted')
        elif args.command == 'show':
            print(json.dumps(engine.get(args.tenant, args.run), indent=2, ensure_ascii=False))
        else:
            print(engine.export_csv(args.tenant, args.run), end='')
    except (ReportError, OSError, json.JSONDecodeError) as exc:
        parser.exit(2, str(exc) + '\n')
    finally:
        engine.close()


if __name__ == '__main__':
    main()
