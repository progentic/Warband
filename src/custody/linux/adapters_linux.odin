package custody_linux

foreign import native "system:warband_custody"

Credentials :: struct {pid: i32, uid, gid: u32}

foreign native {
	wb_lock :: proc(name: cstring, runtime, operator: u32) -> i32 ---
	wb_unlock :: proc() ---
	wb_empty_journal :: proc() -> i32 ---
	wb_size :: proc(name: cstring) -> i64 ---
	wb_read :: proc(name: cstring, buf: rawptr, size: uintptr) -> i32 ---
	wb_append :: proc(buf: rawptr, size: uintptr, first, sync_directory: i32) -> i32 ---
	wb_publish :: proc(buf: rawptr, size: uintptr) -> i32 ---
	wb_sync_history :: proc(truncate_to: i64) -> i32 ---
	wb_listen :: proc(admin: i32) -> i32 ---
	wb_wait :: proc(runtime, admin: i32) -> i32 ---
	wb_accept :: proc(fd: i32) -> i32 ---
	wb_close :: proc(fd: i32) ---
	wb_peer :: proc(fd: i32, p: ^Credentials) -> i32 ---
	wb_request :: proc(fd: i32, buffer: rawptr, capacity: uintptr, complete: ^i32, deadline: i64) -> uintptr ---
	wb_reply :: proc(fd: i32, buffer: rawptr, size: uintptr, deadline: i64) -> i32 ---
	wb_millis :: proc() -> i64 ---
}
