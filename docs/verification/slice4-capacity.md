# Slice 4 capacity checkpoint

Measure source `dcd5c33` on the recorded x64-review target. Sample A after enrollment, provisioning and an empty reconciliation. Sample B after N identical unauthorized enroll requests from the runtime UID. Sample C after a normal import pass. Sample file lengths with all SQLite clients closed and record WAL absence explicitly. Capture head bytes, event/binding counts and watermark at each point. Reject a run unless B retains A's head and event count, custody growth is exactly 203N bytes, C confirms all N bindings and the no-op pass preserves all sampled C fields.

Count application-level event/custody examinations at these measurement-build sites. The custodian counts the history-validation loop, the verify selection loop and validation of an embedded frame during reply encoding. Before sending each reply it writes one counter line (operation and three stage counts) to stderr redirected by systemd to a fixture-private file. The importer counts embedded-frame validation on reply decode, frame inspection by the coordinator, and returned event rows for prefix scan, predecessor comparison and post-COMMIT read-back. It emits one stderr summary per pass. Index, watermark, scalar and aggregate rows are outside the event/custody record count. SQLite page access and internal work for `count(*)` are unmeasured. Budget debits are recorded separately from successful `Session.visits` updates, including the exchange portion. No measurement bytes enter WBCR/WBRS.

**Pre-scaling oracle, N=1.** Empty baseline verify visits the genesis frame twice and costs 3 charged visits. Denial generation validates one frame. During import the four requests (verify, prepare, confirm, verify) validate 2+2+3+4 history frames. Selection visits 2+4, and reply encoding validates one embedded frame. The importer decodes and examines that receipt once each and reads the committed event once. This predicts 21 examinations. The four exchanges debit 5+7+9+9 visits, and the store debits two more. The no-op pass visits 8 validation frames, 6 selection frames, one embedded frame on each side, one coordinator receipt and one prefix row, giving 18 examinations and 19 charges. Any disagreement stops scaling.

Ordinary workloads use fixed request bytes, three repetitions and fresh stores of 50 receipts. For n receipts the predicted import debit is (25n²+33n)/2+3, or 32,078 at n=50. The largest n below the ordinary ceiling is 79. A single n=100 would debit 126,653 visits. Splitting in units of 50 keeps every store the same size and divides all three totals evenly. Target totals of 100, 1,000 and 10,000 are segmented populations. Report n alongside ratios. Keep baseline and no-op costs absolute, and calculate storage rates from actual component deltas (custody history, database and WAL). Endpoint WAL lengths do not measure peak WAL activity.

## Reproduction and raw format

On x64-review, use the landed Linux build scripts for the toolchain, static SQLite archive, custodian, writer-open/provisioning and importer. Export the same ODIN_ROOT, LLVM_CONFIG and PATH as the Linux build. Run these commands from the repository root.

```sh
python3 tests/measurement/build_capacity.py
sudo systemd-run --quiet --scope -p MemoryMax=256M -p MemorySwapMax=0 \
  /usr/bin/python3 tests/measurement/capacity.py samples.jsonl.gz 1 100 1000 10000
python3 tests/measurement/report_capacity.py samples.jsonl.gz
```

The builder instruments a temporary source copy and emits separate binaries. Each raw JSON line identifies the logical total, repetition, physical segment and n. A/B/C sizes are logical bytes in history, database, WAL order. A null WAL length means the file was absent. Counts are events and bindings. The head is the entire head file in hex. Recover the A/B/C custody tips from the first successful verify history scan of the baseline/import/no-op passes respectively. Each scan checks every ordinal from 1 through the tip while the generator is idle. Each custodian tuple gives the WBCR operation, history frames visited, selection frames visited and embedded replies checked. Each importer tuple gives reply checks, coordinator receipt checks, prefix rows, predecessor rows, committed read-backs, exchange charges and total charges. An event joined with its binding is one examined event. Newly encoded output frames and fixture inspection queries are outside the scan count. Denial generation uses identical request bytes and one kernel-observed client process per segment. PIDs and recorded event times vary.

The guest ran Ubuntu 24.04.5 x64 with kernel 6.8.0-142-generic, four QEMU TCG vCPUs, 6144 MiB configured RAM. Local ext4 on /dev/vda1 with `commit=30`, 24 GiB qcow2 on APFS, writeback on, direct off, flush enabled. Available guest space sampled during the run was 20.5 GB. Stores start fresh in a running guest. The guest page cache is not flushed between stores. Custodian and runtime run under distinct UIDs with 32 and 256 MiB memory limits and zero swap. The importer verifies the linked SQLite identity and writing profile on open. Fixture inventory reads use guest Python SQLite 3.45.1. The schema header reported version 1 and 4096-byte pages. Locked Odin commit `8b35c86e`, Clang 19.1.1, SQLite 3.54.1 archive SHA-256 `7e4653fb2880a7262413d61da9fd21db8688c4c38f6da942b0757f3ef9dbc0fb`, default Unix VFS. See the [target record](../engineering/phase2-entry-review.md#linux-development-target-observed-2026-11-18) and [build options](../decisions/0005-event-integrity-acceptance-and-recovery.md#sqlite-static-build-evidence).

## Checkpoint observations

All nine workload repetitions passed on 2026-11-20. The logical totals of 100, 1,000 and 10,000 used 2, 20 and 200 independent stores per repetition. Across 666 ordinary stores (33,300 confirmed imports), all component sizes and per-stage visit counts below matched in every store. The separate single-receipt oracle passed before scaling.

| Phase per physical store (n=50) | Custody history bytes | SQLite database bytes | WAL | Custody tip | Confirmed events / receipt bindings |
| --- | ---: | ---: | --- | ---: | --- |
| A. Enrolled and provisioned | 171 | 20,480 | absent | 1 | 0 / 0 |
| B. Denials retained | 10,321 | 20,480 | absent | 51 | 0 / 0 |
| C. Imports confirmed | 35,421 | 32,768 | absent | 151 | 50 / 50 |

For n=50, B−A was **203 bytes per denial**, all in custody. C−A was **950.76 logical bytes per denial**, comprising 705 in custody (203 for REJECTION plus 251 each for PENDING and COMMITTED), 245.76 in SQLite (three additional 4096-byte pages per store), and zero observed endpoint WAL bytes. The watermark at C was receipt ordinal 51. The initial database pages are included in the A baseline. The per-denial database delta depends on page occupancy at both endpoints.

| Phase per n=50 store | Custodian validation / selection / embedded | Importer decode / receipt inspection | Event rows (prefix / predecessor / read-back) | Actual total | Exchange / other budget debits |
| --- | --- | --- | --- | ---: | --- |
| Empty pass | 1 / 1 / 0 | 0 / 0 | 0 / 0 / 0 | 2 | 3 / 0 |
| Generate denials | 1,275 / 0 / 0 | 0 / 0 | 0 / 0 / 0 | 1,275 | No importer |
| Import | 15,201 / 1,476 / 50 | 50 / 50 | 0 / 49 / 50 | 16,926 | 30,753 / 1,325 |
| No-op pass | 7,701 / 1,476 / 50 | 50 / 50 | 50 / 0 / 0 | 9,377 | 15,453 / 50 |

At n=50 this gives **338.52 actual examinations per newly confirmed event**, against 641.56 charged visits per event (1.8952× charged/observed). The import-pass custody history validation subtotal by request was 5,151 for verify, 5,000 for prepare and 5,050 for confirm. The no-op importer revalidates previously imported receipts, producing 9,377 examinations with zero newly confirmed events. Physical n stays fixed across the segmented totals. Extrapolation to one larger history requires separate measurements.

The [compressed raw observations](slice4-capacity.jsonl.gz) contain one oracle row and 666 ordinary rows. SHA-256 verified on guest and host: `b6eacd6ac3584632a09259018ffda13ebe0cd89133db63a19037e8bd6423fa05`. The instrumented custodian and importer SHA-256 values are `3a9040e40cd8954bb398167bd909f5f3d30849b7033172265377873347214237` and `06cd66cbce62d9b46bf4d1e710b42fb7f1d818cc829baba8115642b4e743655c`. WB-EXC-001 remains Open. Capacity-warning delivery and operator action still require separate evidence.
