package writer_open_test

import "core:testing"
import "../../../src/store"

// Fixture-only access to the same pinned static archive. Production has no create flag.
DIRECTORY :: #config(WARBAND_FIXTURE_DIR, "")
#assert(len(DIRECTORY) > 0)
foreign import fixture_sqlite "warband_sqlite:libsqlite3.a"
Callback :: #type proc "c" (rawptr, i32, [^]cstring, [^]cstring) -> i32
foreign fixture_sqlite {
	sqlite3_open_v2 :: proc(path: cstring, db: ^rawptr, flags: i32, vfs: cstring) -> i32 ---
	sqlite3_exec :: proc(db: rawptr, sql: cstring, callback: Callback, arg: rawptr, error: ^cstring) -> i32 ---
	sqlite3_close :: proc(db: rawptr) -> i32 ---
}

create_fixture :: proc(t: ^testing.T, path, sql: cstring) -> bool {
	db: rawptr
	rc := sqlite3_open_v2(path, &db, 2 | 4, nil) // READWRITE | CREATE
	defer if db != nil { testing.expect(t, sqlite3_close(db) == 0) }
	return testing.expect(t, rc == 0) && testing.expect(t, sqlite3_exec(db, sql, nil, nil, nil) == 0)
}

@(test)
two_connections_report_verified_profiles :: proc(t: ^testing.T) {
	path: cstring = DIRECTORY + "/version-one.db"
	if !create_fixture(t, path, "CREATE TABLE fixture(id INTEGER); PRAGMA user_version=1;") { return }
	first, err1 := store.open_writer(path)
	if !testing.expect_value(t, err1, .None) || !testing.expect(t, first != nil) { return }
	defer testing.expect(t, store.close_writer(&first))
	second, err2 := store.open_writer(path)
	if !testing.expect_value(t, err2, .None) || !testing.expect(t, second != nil) { return }
	defer testing.expect(t, store.close_writer(&second))
	testing.expect(t, first != second)
	expected := store.Profile{journal_mode="wal", synchronous=2, foreign_keys=1, user_version=1}
	testing.expect_value(t, store.writer_profile(first), expected)
	testing.expect_value(t, store.writer_profile(second), expected)
}

check_original_settings :: proc "c" (arg: rawptr, count: i32, values, names: [^]cstring) -> i32 {
	if count != 2 || string(values[0]) != "0" || string(values[1]) != "delete" { return 1 }
	(cast(^int)arg)^ += 1
	return 0
}

@(test)
unversioned_database_keeps_original_journal_mode :: proc(t: ^testing.T) {
	path: cstring = DIRECTORY + "/unversioned.db"
	if !create_fixture(t, path, "PRAGMA journal_mode=DELETE; CREATE TABLE fixture(id INTEGER);") { return }
	writer, err := store.open_writer(path)
	defer testing.expect(t, store.close_writer(&writer))
	testing.expect_value(t, err, .SchemaVersion)
	testing.expect(t, writer == nil)

	db: rawptr
	rc := sqlite3_open_v2(path, &db, 1, nil) // READONLY, independent inspection
	defer if db != nil { testing.expect(t, sqlite3_close(db) == 0) }
	if !testing.expect(t, rc == 0) { return }
	rows := 0
	query: cstring = "SELECT user_version,journal_mode FROM pragma_user_version,pragma_journal_mode"
	testing.expect(t, sqlite3_exec(db, query, check_original_settings, &rows, nil) == 0)
	testing.expect_value(t, rows, 1)
}
