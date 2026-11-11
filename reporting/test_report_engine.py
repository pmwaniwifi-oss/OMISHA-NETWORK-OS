import copy
import json
import tempfile
import unittest
from pathlib import Path

from report_engine import Engine, ReportError, read_json


class ReportingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.engine = Engine(str(Path(self.tmp.name) / 'reports.db'))
        self.template = {'id': 'receipts', 'version': 'v1', 'source': 'erp-import',
                         'columns': [{'header': 'Receipts', 'operation': 'count'},
                                     {'header': 'Total INR', 'operation': 'sum', 'field': 'amount'}]}
        self.records = [{'tenant_id': 'client1', 'source': 'erp-import', 'id': 'r1',
                         'date': '2026-10-01', 'amount': '0.10'},
                        {'tenant_id': 'client1', 'source': 'erp-import', 'id': 'r2',
                         'date': '2026-10-31', 'amount': '0.20'}]
        self.engine.approve_template('client1', self.template, 'reviewer')

    def tearDown(self):
        self.engine.close()
        self.tmp.cleanup()

    def generate(self, records=None):
        return self.engine.generate('client1', 'receipts', 'v1', '2026-10-01',
                                    '2026-10-31', self.records if records is None else records)

    def test_exact_decimal_and_period_boundaries(self):
        records = copy.deepcopy(self.records)
        records.append(dict(records[0], id='excluded', date='2026-11-01', amount='999'))
        result = self.engine.get('client1', self.generate(records))['report']
        self.assertEqual(result['values'], ['2', '0.30'])
        self.assertEqual([r['id'] for r in result['source_records']], ['r1', 'r2'])

    def test_duplicate_and_foreign_tenant_rejected(self):
        for records in (self.records + [self.records[0]],
                        [dict(self.records[0], tenant_id='client2')]):
            with self.assertRaises(ReportError):
                self.generate(records)

    def test_wrong_source_and_missing_amount_rejected(self):
        for record in (dict(self.records[0], source='unknown'),
                       {k: v for k, v in self.records[0].items() if k != 'amount'}):
            with self.assertRaises(ReportError):
                self.generate([record])

    def test_untrusted_decimal_types_rejected(self):
        for value in (True, 0.1, 'NaN', '1e9', '=SUM(A1)', '1,000', ''):
            with self.subTest(value=value), self.assertRaises(ReportError):
                self.generate([dict(self.records[0], amount=value)])

    def test_idempotency_and_source_revision(self):
        run = self.generate()
        self.assertEqual(run, self.generate(list(reversed(self.records))))
        self.assertNotEqual(run, self.generate([dict(self.records[0], amount='0.40')]))

    def test_immutable_template(self):
        changed = copy.deepcopy(self.template)
        changed['columns'][0]['header'] = 'Changed'
        with self.assertRaises(ReportError):
            self.engine.approve_template('client1', changed, 'reviewer')

    def test_export_approval_and_first_approver(self):
        run = self.generate()
        with self.assertRaises(ReportError):
            self.engine.export_csv('client1', run)
        with self.assertRaises(ReportError):
            self.engine.approve('client1', run, 'reviewer', 3)
        self.engine.approve('client1', run, 'reviewer', 2)
        self.engine.approve('client1', run, 'other', 2)
        self.assertEqual(self.engine.get('client1', run)['approved_by'], 'reviewer')
        self.assertEqual(self.engine.export_csv('client1', run), 'Receipts,Total INR\r\n2,0.30\r\n')

    def test_cross_tenant_read_approve_export(self):
        run = self.generate()
        for action in (lambda: self.engine.get('client2', run),
                       lambda: self.engine.approve('client2', run, 'reviewer', 2),
                       lambda: self.engine.export_csv('client2', run)):
            with self.assertRaises(ReportError):
                action()

    def test_integrity_failure(self):
        run = self.generate()
        with self.engine.db:
            self.engine.db.execute("UPDATE runs SET body='{}' WHERE id=?", (run,))
        with self.assertRaises(ReportError):
            self.engine.get('client1', run)

    def test_empty_input_remains_draft_with_warning(self):
        result = self.engine.get('client1', self.generate([]))
        self.assertEqual(result['status'], 'draft')
        self.assertTrue(result['report']['warnings'])

    def test_unsafe_header_exported_as_text(self):
        template = copy.deepcopy(self.template)
        template['version'] = 'v2'
        template['columns'][0]['header'] = '  =1+1'
        self.engine.approve_template('client1', template, 'reviewer')
        run = self.engine.generate('client1', 'receipts', 'v2', '2026-10-01', '2026-10-31', self.records)
        self.engine.approve('client1', run, 'reviewer', 2)
        self.assertTrue(self.engine.export_csv('client1', run).startswith("'  =1+1,"))

    def test_period_and_unapproved_template(self):
        for tenant, start, end in [('client1', '2026-10-31', '2026-10-01'),
                                   ('client1', '2026-02-30', '2026-10-31'),
                                   ('client2', '2026-10-01', '2026-10-31')]:
            with self.assertRaises(ReportError):
                self.engine.generate(tenant, 'receipts', 'v1', start, end, [])

    def test_duplicate_json_keys_rejected(self):
        path = Path(self.tmp.name) / 'input.json'
        path.write_text('{"amount":"1","amount":"2"}')
        with self.assertRaises(ReportError):
            read_json(path)

    def test_state_survives_reopen(self):
        run = self.generate()
        self.engine.approve('client1', run, 'reviewer', 2)
        self.engine.close()
        self.engine = Engine(str(Path(self.tmp.name) / 'reports.db'))
        self.assertEqual(self.engine.get('client1', run)['status'], 'approved')


if __name__ == '__main__':
    unittest.main()
