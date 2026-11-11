# ISP log storage: lossless archive foundation

Status: first storage primitive, 10 November 2026. Not a certified IPDR collector,
retention engine, production archive, or legal determination for this operator.

## Regulatory baseline and decision gate

- The DoT UL compendium updated through 31 March 2024, Internet Service clauses
  7.1/7.2, states a minimum two years for Internet CDR/IPDR and subscriber
  login/logout records. Clause 39.20 permits longer preservation when directed.
- CERT-In's 28 April 2022 direction (iv) requires secure ICT-system logs for a
  rolling 180 days within Indian jurisdiction. This does not shorten a longer
  telecom-license retention requirement.
- Match the actual operator's UL/UL-VNO/ISP authorization, amendments, current
  IPDR field specification and LSA directions before assigning production policy.
  A generic two-year default is not proof of compliance for every log class.
- Legal/investigation holds override ordinary expiry. No deletion is implemented.
- Sources were checked on 10 November 2026 using indexed official text. Direct
  PDF retrieval was restricted/timed out; exact operator applicability and later
  amendments still require confirmation.

Official references:

- https://eservices.dot.gov.in/sites/default/files/circular-notifications/Compendium-UL-AGREEMENT%20updated%20up%20to%2031032024.pdf
- https://www.cert-in.org.in/PDF/CERT-In_Directions_70B_28.04.2022.pdf
- https://www.cert-in.org.in/Directions70B.jsp

## Storage design

1. Collect into a durable disk-backed spool, with loss/backlog counters. RAM-only
   storage and silent UDP/drop handling cannot supply a reliable archive.
2. Rotate by rename and have the writer close/reopen its file. Never compress a
   live file and then truncate it. Archive only immutable closed segments.
3. Compress every original byte with Zstandard. Do not sample, remove required
   fields, round timestamps or drop interim accounting records for space savings.
4. Read the compressed archive back, decompress and compare original length and
   SHA-256 before publishing a completed archive directory.
5. Store segments per tenant/log class/date. The initial date partition is the
   ARCHIVE creation date, not an extracted event-time or legal-retention cutoff.
6. Keep only a measured recent search window in the hot query store; keep the
   complete compressed record set for the approved full retention interval.
   Parquet/Zstd projections may later accelerate search; they do not replace raw
   evidence until field fidelity and the required export format are validated.
7. Protect archives with encryption, independent backup and signed/immutable
   manifests under separate credentials. A SHA-256 alongside a writable file is
   corruption detection, not proof against malicious alteration.
8. Rehearse retrieval by subscriber/session and public-IP + port + protocol +
   exact time. Correlate NAT allocation, subscriber mapping and session events.
   Validate the full applicable IPDR field set, not just those lookup keys.
9. Synchronize clocks and record timezone/time-source quality. Record lineage,
   source sequence/gaps and late-event handling in the eventual collector.

The `logging/log_archive.py` tool implements steps 3/4 and tenant-labelled
directories only. It does not parse IPDR, create a query index, encrypt archives,
sign manifests, enforce filesystem tenant isolation, or perform remote backups.
It checks tenant labels on verification; OS credentials/ACLs must isolate tenants.
It neither deletes nor truncates the source. Initially total disk use increases
because both source and archive exist. Reclaiming a redundant source copy is a
future audited lifecycle step after custody, recovery and policy gates pass.

## Pilot commands (closed test logs only)

Use a supported Linux VM, Python 3.12 and an isolated Python environment.

```bash
python -m pip install -r logging/requirements.txt
python logging/log_archive.py pack /path/to/closed-test.log \
  --output /path/to/private-archive --tenant demo-client \
  --source-id lab-nas-1 --log-type ipdr --sealed --level 3
python logging/log_archive.py verify /path/returned/by/pack --tenant demo-client
```

`--sealed` is an operator assertion that the writer has closed the file, not a
mechanism that stops a live writer. A detected source mutation aborts publication.
No automatic collector, scheduled task, production filesystem or network service
is changed by these commands. Do not put real logs or manifests in public GitHub.

## Capacity and acceptance

Measure representative, sanitized closed logs for 24-72 hours. Benchmark levels
1, 3 and 6: bytes, CPU time, compression and restore throughput, peak memory.
Use random/variable timestamps, subscriber IDs, NAT ports and real record shapes;
repeated synthetic lines exaggerate compression and are only correctness tests.

Archive capacity = raw bytes/day x retention days / measured compression ratio.
Add hot-store indexes, durable spool, backup copies, redundancy and headroom.
For illustration only: 100 GB/day x 730 / 5 = 14.6 TB for one archive copy;
two copies = 29.2 TB before indexes, redundancy and headroom. This assumes a
measured 5:1 ratio; 730 days is sizing arithmetic, not the legal deletion rule.

Release acceptance: exact-byte recovery; corruption and wrong-tenant rejection;
no source deletion on any error; crash/disk-full and writer-rotation tests;
independent backup restore; operator-approved retention/hold/export requirements.
The current tests cover the first three, not the complete production gate.

Codec references:

- https://meta.github.io/zstd/
- https://python-zstandard.readthedocs.io/en/latest/compressor.html
- https://parquet.apache.org/docs/file-format/data-pages/compression/
