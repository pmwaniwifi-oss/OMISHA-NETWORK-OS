# OMISHA reporting core: offline pilot

Working scope: explicit JSON mapping, immutable approved template versions,
inclusive date filtering, exact decimal sums and row counts, source snapshots,
idempotent generation, persisted review state, reconciliation count and CSV export.
This is not a government-prescribed format, tax calculator or certified report.
Counting rows does not mean counting unique subscribers. Each approved mapping
must explicitly define what a row represents. Importer completeness and financial
reconciliation remain operator responsibilities.

Run with Python 3.12; no third-party dependency or network service is needed.
Use a private directory (0700) and umask 077. SQLite stores report values and
source references in plaintext: keep its volume encrypted and backed up. Do not commit the database,
exports, actual email attachments, signatures or customer records to public GitHub.

```bash
umask 077
mkdir -p runtime/reporting
python reporting/report_engine.py --db runtime/reporting/pilot.db --tenant demo approve-template --file reporting/template.example.json --actor operator
python reporting/report_engine.py --db runtime/reporting/pilot.db --tenant demo generate --template receipts --version v1 --start 2026-10-01 --end 2026-10-31 --records reporting/records.example.ndjson
# Copy the printed run ID into RUN_ID; inspect before approving.
python reporting/report_engine.py --db runtime/reporting/pilot.db --tenant demo show --run "$RUN_ID"
python reporting/report_engine.py --db runtime/reporting/pilot.db --tenant demo approve --run "$RUN_ID" --actor operator --confirmed-count 2
python reporting/report_engine.py --db runtime/reporting/pilot.db --tenant demo export --run "$RUN_ID" > runtime/reporting/demo.csv
python -m unittest discover -s reporting -p 'test_*.py' -v
```

Expected sample output: count 2 and total 300.30. Data is synthetic. Do not submit
it to any authority. Templates and NDJSON input are limited to 16 MiB, each line
to 1 MiB and imports to 100,000 rows; the engine is a pilot, not an IPDR analytics
engine. NDJSON rows are parsed and aggregated one at a time. Input rows are not
copied into report runs. Persisted provenance contains source system,
record ID, date and an input hash; the source transaction stays in its owning
system. Later adapters should query bounded aggregates and retain archive refs.

A Dockerfile is included for the same offline CLI. It opens no ports and has no
runtime network requirement. Build with `docker build -t omisha-reporting reporting`.
Mount inputs read-only and a dedicated private output directory read-write; the
default container UID is 10001 and requires matching output-directory ownership.
Run with `--network none --read-only --cap-drop ALL --security-opt no-new-privileges`.
The inherited Python base tag must be locked to an approved digest before release.

## Security boundary

The CLI is for one trusted local operator. `--actor` records an asserted name;
it does not authenticate a person or authorize a signature. Tenant predicates are
tested but any OS user with DB access can read/change all tenants. Hashes detect
accidental payload corruption, not a hostile database administrator. Production
must add authenticated roles, tenant-bound service credentials, independent audit
storage, protected approval state and per-client isolation before exposure.
No HTTP listener, email sender, uploaded signature, DSC, AI model, cron daemon or
government-portal integration is implemented by this module.

## Next implementation contracts

1. ERPNext adapter supplies posted, reconciled records with stable source IDs;
   NMS/PM-WANI adapters supply agreed aggregates from supported APIs. The report
   engine must never rewrite GL or provision services.
2. Authenticated Go BFF obtains tenant and actor from verified identity. Frappe
   owns production approval documents and transactional outbox. Do not expose this
   CLI or SQLite directly to untrusted users.
3. Upload UI quarantines files, enforces format/size limits, rejects macros and
   external links, and runs parsers/OCR without network access. AI proposes a
   bounded mapping; it cannot execute SQL, code or email instructions. Approved
   mappings remain deterministic and versioned.
4. Scheduler stores timezone, frequency, reporting window, due date, cutoff and
   retry state. Unique job identity includes tenant/template/version/period;
   changed source snapshots create revisions requiring new approval. Late data,
   missed schedules and repeated deliveries must be visible.
5. Email intake reads only an authorised mailbox/folder. Sender identity alone is
   not authorization. Bind requests to tenant, allowlisted report types and known
   recipient entitlement; uncertain dates or definitions enter clarification.
   Persist provider message ID for deduplication. Attachments and body are data,
   never executable instructions. External AI use requires explicit data policy.
6. Signature image permissions and DSC/eSign integration are separate. Bind
   approval to final output digest; modifications invalidate approval. Expired or
   revoked authorisation blocks signing. Never store signing keys in templates.
7. Outgoing email requires an approved final artifact and verified recipients.
   Store send attempt/provider ID, receipt and acknowledgement separately. Retries
   must reconcile ambiguous send outcomes before sending again. This CLI does not
   send emails. Export is not submission or government acknowledgement.

## Release gates

- Real department template, reporting definitions and applicability confirmed.
- Identity/tenant tests at API and database layers; no cross-client exports.
- Template/schema change forces review; missing amounts never become zero.
- Financial totals and expected population reconcile against authoritative data.
- Crash/retry tests for scheduler and mail outbox, missed-run alerts.
- Restored backups reproduce a prior approved artifact; independent audit proof.
- Actual government format validation, human sign-off and acknowledgement captured.

GST returns, PM-WANI protocol compliance, statutory report applicability and
mandatory retention cannot be inferred from a sample template or this engine.
