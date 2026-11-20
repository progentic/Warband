#+private
package store

import "core:mem"

foreign import sqlite "warband_sqlite:libsqlite3.a"

Database :: distinct rawptr
Statement :: distinct rawptr

foreign sqlite {
	sqlite3_libversion_number :: proc() -> i32 ---
	sqlite3_sourceid :: proc() -> cstring ---
	sqlite3_compileoption_used :: proc(option: cstring) -> i32 ---
	sqlite3_open_v2 :: proc(path: cstring, db: ^Database, flags: i32, vfs: cstring) -> i32 ---
	sqlite3_db_readonly :: proc(db: Database, name: cstring) -> i32 ---
	sqlite3_exec :: proc(db: Database, sql: cstring, callback: #type proc "c" (rawptr, i32, [^]cstring, [^]cstring) -> i32, arg: rawptr, error: ^cstring) -> i32 ---
	sqlite3_close :: proc(db: Database) -> i32 ---
	sqlite3_prepare_v2 :: proc(db: Database, sql: cstring, length: i32, stmt: ^Statement, tail: ^cstring) -> i32 ---
	sqlite3_step :: proc(stmt: Statement) -> i32 ---
	sqlite3_column_type :: proc(stmt: Statement, column: i32) -> i32 ---
	sqlite3_column_int64 :: proc(stmt: Statement, column: i32) -> i64 ---
	sqlite3_column_text :: proc(stmt: Statement, column: i32) -> cstring ---
	sqlite3_finalize :: proc(stmt: Statement) -> i32 ---
}

READWRITE :: 2
ROW :: 100
DONE :: 101
INTEGER :: 1
TEXT :: 3
SOURCE_ID :: "2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76"

library_matches_pin :: proc() -> bool {
	return sqlite3_libversion_number() == 3054001 &&
	       string(sqlite3_sourceid()) == SOURCE_ID &&
	       sqlite3_compileoption_used("THREADSAFE=1") != 0 &&
	       sqlite3_compileoption_used("OMIT_LOAD_EXTENSION") != 0 &&
	       sqlite3_compileoption_used("DQS=0") != 0
}

WriterState :: struct {
	db: Database,
	profile: Profile,
	allocator: mem.Allocator,
}

open_existing :: proc(path: cstring) -> (^WriterState, OpenError) {
	db: Database
	result := sqlite3_open_v2(path, &db, READWRITE, nil)
	// Even a failed SQLite open can return a connection that needs closing.
	transferred := false
	defer if db != nil && !transferred { _ = sqlite3_close(db) }
	if result != 0 { return nil, .OpenFailed }
	if sqlite3_db_readonly(db, "main") != 0 { return nil, .ReadOnly }
	state, err := new(WriterState, context.allocator)
	if err != nil { return nil, .Allocation }
	state^ = {db=db, allocator=context.allocator}
	transferred = true
	return state, .None
}

release_connection :: proc(state: ^WriterState) -> bool {
	if sqlite3_close(state.db) != 0 { return false }
	free(state, state.allocator)
	return true
}

// Each fixed profile query must produce exactly one typed value and then finish.
// Copy the recognized WAL name before the statement's text storage is released.
Scalar :: union {i64, string}
read_scalar :: proc(state: ^WriterState, sql: cstring) -> Scalar {
	stmt: Statement
	if sqlite3_prepare_v2(state.db, sql, -1, &stmt, nil) != 0 { return nil }
	value: Scalar
	if sqlite3_step(stmt) == ROW {
		switch sqlite3_column_type(stmt, 0) {
		case INTEGER: value = sqlite3_column_int64(stmt, 0)
		case TEXT:
			if string(sqlite3_column_text(stmt, 0)) == "wal" { value = "wal" }
		}
		if sqlite3_step(stmt) != DONE { value = nil }
	}
	if sqlite3_finalize(stmt) != 0 { return nil }
	return value
}

set_connection_option :: proc(state: ^WriterState, sql: cstring) -> bool {
	stmt: Statement
	if sqlite3_prepare_v2(state.db, sql, -1, &stmt, nil) != 0 { return false }
	completed := sqlite3_step(stmt) == DONE
	return sqlite3_finalize(stmt) == 0 && completed
}


// sqlite3_exec stops at the first failed statement. Closing the connection
// rolls back any transaction still open after an error.
install_schema_v1 :: proc(state: ^WriterState) -> bool {
	schema :: #load("schema_v1.sql", string) + "\x00"
	return sqlite3_exec(state.db, cstring(raw_data(schema)), nil, nil, nil) == 0
}
