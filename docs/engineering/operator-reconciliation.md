# Operator rehearsal for halted Phase 2 stores

Use this procedure on isolated x64-review working copies. Record the operator, date, target, source commit and inventory digest for each case. The importer reports whether protected work can proceed. Replay separately describes what the confirmed prefix establishes.

1. Stop admission and quiesce the runtime writer and custodian before taking or selecting the evidence. Keep them offline on the source. Preserve the full custody directory, published head, SQLite database and all present WAL/SHM/journal files together. The point 2 capture was taken immediately after reaping the writer, before diagnostic reads. For the crafted case, the fixture commits and closes its SQLite transaction before export. No producer uses either sealed bundle.
2. Obtain the expected inventory digest from the originating run log. For the original x64-review point 2 capture, use the digest in the [matrix](../verification/phase2-crash-coverage.md#evidence-key). Record which sidecars were present. Verify the SHA-256 of the inventory itself and each listed file. Open SQLite only on a disposable working copy.
3. From the built checkout run the inspection below for each trusted bundle. Supply the absolute bundle path and its expected digest. It verifies the inventory, restores the bytes under isolated service identities, uses authenticated Verify, reads the rows, runs the normal importer and replay, shuts down the working custodian and checks the source inventory again.

   ```sh
   sudo systemd-run --quiet --scope -p MemoryMax=256M -p MemorySwapMax=0 \
     /usr/bin/python3 tests/integration/linux/operator_rehearsal.py "$bundle" "$inventory_sha256"
   ```

4. Compare the full store/epoch/sequence Ref and event digest in the report with the custody checkpoint, pending record hash and SQLite evidence. For **PendingEventMissing**, require the actual tip-3 PENDING frame, a sequence-zero checkpoint, and zero event, binding and watermark rows. The pledge supplies a digest but cannot recover the missing canonical event or its recorded time. For **UnattestedTail**, require an empty pending tuple and a sequence-zero checkpoint alongside the unconfirmed SQLite suffix. Its fixture constructs a canonical denial import from a real receipt and inserts the event, binding and watermark in SQLite without Prepare or Confirm.
5. Record a separate operator decision and reason for each inventory. State whether any independently trusted evidence or separately authorized recovery action permits resumption. Where prerequisites are missing, continue the halt, preserve the pledge or suffix, and keep protected work withheld. Resume only under the applicable authorized procedure and record its evidence. Never cancel the pledge automatically, trim an unattested SQLite suffix, attest it retroactively or redispatch uncertain work.
6. Recheck both original inventories after the decision. Keep the reports and signed-off dispositions with the [rehearsal record](../verification/phase2-crash-coverage.md#operator-reconciliation-rehearsal). Hosted CI exercises inspection and preservation. The named operator owns the decision.
