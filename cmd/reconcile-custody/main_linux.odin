package main

import "core:os"
import "core:sys/linux"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:strconv"
import "core:encoding/hex"
import e "../../src/domain/events"
import r "../../src/runtime"
import c "../../src/runtime/client"
import s "../../src/store"

TEST_STOP_SIGNAL :: linux.Signal.SIGSTOP

workspace: [128*1024*1024]u8

main :: proc() {
	arena: mem.Arena
	mem.arena_init(&arena,workspace[:])
	context.allocator = mem.arena_allocator(&arena)
	// Paths and epoch handoff evidence come from trusted operator configuration.
	args := os.args
	if len(args)<8 || (len(args)-8)%2 != 0 {
		fmt.eprintln("usage: reconcile-custody DB SOCKET CUSTODIAN_UID STORE EPOCH RETRY_ORDINAL RETRY_HASH_OR_- [OLD_DB EPOCH_WBCR_HEX]...")
		os.exit(2)
	}
	if !strings.has_prefix(args[1],"/") || !strings.has_prefix(args[2],"/") { os.exit(2) }
	uid,u := strconv.parse_uint(args[3],10)
	epoch,v := strconv.parse_uint(args[5],10)
	ord,o := strconv.parse_uint(args[6],10)
	store_bytes,b := hex.decode(transmute([]u8)args[4])
	if !u || uid>uint(max(u32)) || !v || epoch==0 || !o || !b || len(store_bytes)!=16 { os.exit(2) }
	session := c.Session{path=strings.clone_to_cstring(args[2]),uid=u32(uid),epoch=e.Epoch(epoch)}
	copy(session.store[:],store_bytes)
	retry: Maybe(s.ReceiptId)
	if ord != 0 {
		hash,h := hex.decode(transmute([]u8)args[7])
		if !h || len(hash)!=32 { os.exit(2) }
		id := s.ReceiptId{ordinal=u64(ord)}
		copy(id.hash[:],hash)
		retry = id
	} else if args[7] != "-" { os.exit(2) }
	archives: [dynamic]r.Archive
	for i:=8; i<len(args); i+=2 {
		if !strings.has_prefix(args[i],"/") || len(args[i+1])>2394 { os.exit(2) }
		wire,ok := hex.decode(transmute([]u8)args[i+1])
		if !ok { os.exit(2) }
		if _, err := append(&archives,r.Archive{strings.clone_to_cstring(args[i]),wire}); err != nil { os.exit(2) }
	}
	ref: e.EventRef
	result := r.run(strings.clone_to_cstring(args[1]),&session,archives[:],retry,&ref)
	when #config(WARBAND_TEST_STOP_BEFORE_ACK, false) {
		if result == .Ready && linux.kill(linux.getpid(), TEST_STOP_SIGNAL) != .NONE { os.exit(1) }
	}
	if ref.sequence != 0 && (result == .ConfirmedResponsePending || result == .PendingConfirmation) {
		fmt.println(result,args[4],u64(ref.epoch),u64(ref.sequence))
	} else { fmt.println(result) }
	if result != .Ready && result != .PendingConfirmation && result != .ConfirmedResponsePending { os.exit(1) }
}
