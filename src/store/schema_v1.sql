BEGIN IMMEDIATE;
CREATE TABLE events (
  store_id BLOB NOT NULL CHECK(length(store_id)=16 AND store_id<>zeroblob(16)),
  epoch BLOB NOT NULL CHECK(length(epoch)=8 AND epoch<>zeroblob(8)),
  sequence BLOB NOT NULL CHECK(length(sequence)=8 AND sequence<>zeroblob(8)),
  canonical_event BLOB NOT NULL,
  PRIMARY KEY (store_id, epoch, sequence)
) STRICT, WITHOUT ROWID;
CREATE TABLE denial_imports (
  store_id BLOB NOT NULL,
  custody_ordinal BLOB NOT NULL CHECK(length(custody_ordinal)=8 AND custody_ordinal<>zeroblob(8)),
  record_hash BLOB NOT NULL CHECK(length(record_hash)=32),
  epoch BLOB NOT NULL, sequence BLOB NOT NULL,
  PRIMARY KEY (store_id, custody_ordinal),
  UNIQUE (store_id, epoch, sequence),
  FOREIGN KEY (store_id, epoch, sequence) REFERENCES events(store_id, epoch, sequence)
) STRICT, WITHOUT ROWID;
CREATE TABLE import_watermarks (
  store_id BLOB PRIMARY KEY,
  last_imported_ordinal BLOB NOT NULL,
  FOREIGN KEY (store_id, last_imported_ordinal) REFERENCES denial_imports(store_id, custody_ordinal)
) STRICT, WITHOUT ROWID;
PRAGMA user_version=1;
COMMIT;
