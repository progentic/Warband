package store

// Owned by the successful opener. Close once, after the last use.
VerifiedWriter :: distinct ^struct {}
Profile :: struct {
	journal_mode: string,
	synchronous, foreign_keys, user_version: i64,
}

OpenError :: enum {None, LibraryIdentity, OpenFailed, ReadOnly, SchemaVersion, ConnectionProfile, Allocation}

open_writer :: proc(path: cstring) -> (VerifiedWriter, OpenError) {
	if !library_matches_pin() { return nil, .LibraryIdentity }

	state, err := open_existing(path)
	if err != .None { return nil, err }
	verified := false
	defer if !verified { _ = release_connection(state) }
	if read_scalar(state, "PRAGMA user_version") != i64(1) { return nil, .SchemaVersion }

	if read_scalar(state, "PRAGMA journal_mode=WAL") != "wal" ||
	   !set_connection_option(state, "PRAGMA synchronous=FULL") ||
	   !set_connection_option(state, "PRAGMA foreign_keys=ON") { return nil, .ConnectionProfile }

	mode, mode_ok := read_scalar(state, "PRAGMA journal_mode").(string)
	sync, sync_ok := read_scalar(state, "PRAGMA synchronous").(i64)
	keys, keys_ok := read_scalar(state, "PRAGMA foreign_keys").(i64)
	version, version_ok := read_scalar(state, "PRAGMA user_version").(i64)
	if !mode_ok || !sync_ok || !keys_ok || !version_ok || mode != "wal" || sync != 2 || keys != 1 || version != 1 {
		return nil, .ConnectionProfile
	}

	state.profile = {mode, sync, keys, version}
	verified = true
	return cast(VerifiedWriter)state, .None
}

// Snapshot read back on this writer at open. Returned by value.
writer_profile :: proc(writer: VerifiedWriter) -> Profile {
	return (cast(^WriterState)writer).profile
}

close_writer :: proc(writer: ^VerifiedWriter) -> bool {
	if writer^ == nil { return true }
	state := cast(^WriterState)writer^
	// No outstanding statements escape the private binding.
	if !release_connection(state) { return false }
	writer^ = nil
	return true
}
