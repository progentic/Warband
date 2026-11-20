package store

import "core:fmt"
import "core:os"

ProvisionError :: enum {None, AlreadyExists, AcquireFailed, LibraryIdentity, OpenFailed, ForeignKeys, Schema, CloseFailed}

// Operator owns the quiesced, enrolled journal directory throughout this call.
provision_store :: proc(path: cstring) -> ProvisionError {
	name := string(path)
	if len(name) == 0 { return .AcquireFailed }
	// Prefix relative filenames so SQLite treats even ":memory:" as a disk path.
	filename := path
	if name[0] != '/' {
		filename = fmt.caprintf("./%s", name)
	}
	defer if filename != path { delete(filename) }

	file, err := os.open(string(filename), {.Read, .Write, .Create, .Excl}, {.Read_User, .Write_User})
	if err == .Exist { return .AlreadyExists }
	if err != nil { return .AcquireFailed }
	if os.close(file) != nil { return .CloseFailed }
	if !library_matches_pin() { return .LibraryIdentity }
	state, open_error := open_existing(filename)
	if open_error != .None { return .OpenFailed }
	result := ProvisionError.None
	if !set_connection_option(state, "PRAGMA foreign_keys=ON") ||
	   read_scalar(state, "PRAGMA foreign_keys") != i64(1) {
		result = .ForeignKeys
	} else if !install_schema_v1(state) {
		result = .Schema
	}
	if !release_connection(state) { return .CloseFailed }
	return result
}
