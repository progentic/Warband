package main

import "core:encoding/hex"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import r "../../src/runtime"
import c "../../src/runtime/client"
import e "../../src/domain/events"

workspace: [128*1024*1024]u8

main :: proc() {
	arena: mem.Arena
	mem.arena_init(&arena,workspace[:])
	context.allocator = mem.arena_allocator(&arena)
	args := os.args
	provision := len(args)==7 && args[6]=="provision-index"
	if !provision && (len(args)<9 || (len(args)-9)%2 != 0) {
		fmt.eprintln("usage: accept-noop DB SOCKET CUSTODIAN_UID STORE EPOCH {provision-index | EVALUATION_SEQUENCE TASK_VERSION CONTROL_REVISION [OLD_DB EPOCH_WBCR_HEX]...}")
		os.exit(2)
	}
	if !strings.has_prefix(args[1],"/") || !strings.has_prefix(args[2],"/") { os.exit(2) }
	uid,u := strconv.parse_uint(args[3],10)
	epoch,v := strconv.parse_uint(args[5],10)
	sequence,task,control: uint
	if !provision {
		var_ok: bool
		sequence,var_ok = strconv.parse_uint(args[6],10)
		if !var_ok || sequence==0 { os.exit(2) }
		task,var_ok = strconv.parse_uint(args[7],10)
		if !var_ok { os.exit(2) }
		control,var_ok = strconv.parse_uint(args[8],10)
		if !var_ok { os.exit(2) }
	}
	id,hex_ok := hex.decode(transmute([]u8)args[4])
	if !u || uid>uint(max(u32)) || !v || epoch==0 || !hex_ok || len(id)!=16 { os.exit(2) }
	session := c.Session{path=strings.clone_to_cstring(args[2]),uid=u32(uid),epoch=e.Epoch(epoch)}
	copy(session.store[:],id)
	segments: [dynamic]r.Archive
	for i:=9; i<len(args); i+=2 {
		if !strings.has_prefix(args[i],"/") || len(args[i+1])>2394 { os.exit(2) }
		wire,ok := hex.decode(transmute([]u8)args[i+1])
		if !ok { os.exit(2) }
		if _, err := append(&segments,r.Archive{strings.clone_to_cstring(args[i]),wire}); err != nil { os.exit(2) }
	}
	requested := e.EventRef{session.store,session.epoch,e.Sequence(sequence)}
	result,event := r.run_acceptor(strings.clone_to_cstring(args[1]),&session,segments[:],requested,u64(task),u64(control),provision)
	if result==.Accepted || result==.Recorded {
		fmt.println(result,args[4],epoch,u64(event.reference.sequence),string(hex.encode(event.transition[:])),
		            event.expected_task_version+1,event.expected_control_revision+1)
	} else {
		fmt.println(result)
		if result!=.IndexVerified { os.exit(1) }
	}
}
