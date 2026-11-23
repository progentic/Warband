package reconcile

import a "../audit"
import c "../custody"
import e "../domain/events"
import r "../replay"
import store "../store"
import client "client"
import "core:crypto/sha2"
import "core:encoding/endian"
import "core:encoding/hex"
import "core:strings"
import "core:mem"
import l "core:sys/linux"

IntakeOutcome :: enum {Unavailable, Ready, OperationDeadlineExceeded, AttestationUncertain, ConfirmedProposal, AlreadyProposed, ExistingTask, DirectoryHold, PendingEventMissing,
                       PendingConfirmation, RecoveredConfirmation, UnattestedTail, IntegrityFault, RecoveryLimitExceeded, LockUnavailable}
PreparedProposal :: struct {proposal: a.MarkerProposal, directory_fd: l.Fd, projection: r.Projection}
@(private)
IntakeDB :: "./journal/active.db"
@(private)
DirectoryFlags :: l.Open_Flags{.DIRECTORY,.NOFOLLOW,.CLOEXEC}

// The trusted launcher selects cwd. Only stdin is proposal input.
@(private)
intake_configuration :: proc() -> (e.Checkpoint,u32,bool) {
	st: l.Stat
	uid := l.getuid()
	if uid==0 || l.stat(".",&st)!=.NONE || st.uid!=0 || transmute(u32)st.mode&0o022!=0 { return {},0,false }
	fd,err := l.open("intake.anchor",{.NOFOLLOW,.CLOEXEC,.NONBLOCK})
	if err!=.NONE { return {},0,false }
	defer l.close(fd)
	if l.fstat(fd,&st)!=.NONE || !l.S_ISREG(st.mode) || st.uid!=0 || st.nlink!=1 || transmute(u32)st.mode&0o022!=0 || st.size!=68 { return {},0,false }
	b: [68]u8
	n,re := l.read(fd,b[:])
	if re!=.NONE || n!=len(b) { return {},0,false }
	epoch,_ := endian.get_u64(b[16:24],.Little)
	seq,_ := endian.get_u64(b[24:32],.Little)
	cust,_ := endian.get_u32(b[64:],.Little)
	if epoch!=1 || seq!=0 || cust==0 || cust==u32(uid) { return {},0,false }
	if l.lstat("endpoints",&st)!=.NONE || !l.S_ISDIR(st.mode) || u32(st.uid)!=cust || transmute(u32)st.mode&0o022!=0 { return {},0,false }
	if l.lstat("journal",&st)!=.NONE || !l.S_ISDIR(st.mode) || st.uid!=uid || transmute(u32)st.mode&0o7777!=0o700 { return {},0,false }
	root := e.Checkpoint{epoch=1}
	copy(root.store[:],b[:16])
	copy(root.head[:],b[32:64])
	return root,cust,root.store!=(e.StoreId{})
}

@(private)
private_dir :: proc(fd: l.Fd) -> (l.Stat,bool) {
	st: l.Stat
	ok := l.fstat(fd,&st)==.NONE && l.S_ISDIR(st.mode) && st.uid==l.getuid() && transmute(u32)st.mode&0o7777==0o700
	return st,ok
}

@(private)
attempt_entry :: proc(fd: l.Fd) -> (string,bool) {
	found := ""
	buf: [4096]u8
	for {
		n,err := l.getdents(fd,buf[:])
		if err!=.NONE { return "",false }
		if n==0 { return found,true }
		offset := 0
		for entry in l.dirent_iterate_buf(buf[:n],&offset) {
			name := l.dirent_name(entry)
			if name=="." || name==".." { continue }
			if found!="" || len(name)!=32 { return "",false }
			for ch in name {
				if !(ch>='0' && ch<='9' || ch>='a' && ch<='f') { return "",false }
			}
			st: l.Stat
			if l.fstatat(fd,strings.clone_to_cstring(name),&st,{.SYMLINK_NOFOLLOW})!=.NONE ||
			   !l.S_ISDIR(st.mode) || st.uid!=l.getuid() || transmute(u32)st.mode&0o7777!=0o700 { return "",false }
			found = strings.clone(name)
		}
	}
}

@(private)
attempt_dir :: proc(parent: l.Fd,p: ^a.MarkerProposal,create: bool,unused := true) -> (l.Fd,bool) {
	name := strings.clone_to_cstring(string(hex.encode(p.directory[:])))
	if create && l.mkdirat(parent,name,transmute(l.Mode)u32(0o700))!=.NONE { return -1,false }
	fd,err := l.openat(parent,name,DirectoryFlags)
	if err!=.NONE { return -1,false }
	st,ok := private_dir(fd)
	leaf: l.Stat
	if !ok || (unused && l.fstatat(fd,"marker",&leaf,{.SYMLINK_NOFOLLOW})!=.ENOENT) ||
	   (!create && (p.device!=u64(st.dev) || p.inode!=u64(st.ino))) ||
	   (create && (l.fsync(fd)!=.NONE || l.fsync(parent)!=.NONE)) {
		l.close(fd)
		return -1,false
	}
	p.device,p.inode = u64(st.dev),u64(st.ino)
	return fd,true
}

@(private)
IntakeSnapshot :: struct {
	cp: e.Checkpoint, pending: Maybe(e.Pledge), rows: []r.Row, receipts: [dynamic]r.Receipt,
	replay: r.Result, mark: u64, tail_import: Maybe(store.Import),
}

@(private)
intake_snapshot :: proc(w: store.VerifiedWriter,s: ^client.Session,root: e.Checkpoint) -> (IntakeSnapshot,IntakeOutcome) {
	page,ok := client.verify(s,0)
	if !ok { return {},.Unavailable }
	snap := IntakeSnapshot{cp=page.committed,pending=page.pending}
	imports: [dynamic]store.Import
	defer delete(imports)
	seg,checked := store.inspect_writer(w,snap.cp,root.head,&imports,s,marker=true)
	if !checked || !store.watermark_matches(w,s.store,seg.last_import) { return {},.IntegrityFault }
	snap.mark,snap.tail_import = seg.last_import,seg.tail_import
	tip := page.tip
	for {
		frame,present := page.rejection.(c.RejectionFrameBytes)
		if !present { break }
		seen := receipt(frame)
		if seen.id.ordinal>tip { break }
		i := len(snap.receipts)
		if i<len(imports) && (seen.id!=imports[i].id || seen.digest!=imports[i].digest) { return {},.IntegrityFault }
		epoch,_ := endian.get_u64(frame[99:107],.Little)
		if _,err := append(&snap.receipts,r.Receipt{e.Epoch(epoch),seen.digest}); err!=nil { return {},.Unavailable }
		page,ok = client.verify(s,seen.id.ordinal)
		if !ok || page.committed!=snap.cp || page.pending!=snap.pending || page.tip<tip { return {},.IntegrityFault }
	}
	if len(imports)>len(snap.receipts) { return {},.IntegrityFault }
	snap.rows,_,ok = store.read_replay_segment(IntakeDB,{s.store,1,0},s,nil)
	if !ok { return {},.IntegrityFault }
	p,active := snap.pending.(e.Pledge)
	ptr: ^e.Pledge
	if active { ptr=&p }
	segments := [?]r.Segment{{rows=snap.rows}}
	snap.replay = r.project_markers(root,snap.cp,ptr,segments[:],snap.receipts[:])
	if !client.within_budget(s) { return {},.RecoveryLimitExceeded }
	if snap.replay.readiness==.UnattestedTail { return snap,.UnattestedTail }
	if snap.replay.error!=.None { return {},.IntegrityFault }
	#partial switch snap.replay.readiness {
	case .PendingEventMissing: return snap,.PendingEventMissing
	case .PendingConfirmation: return snap,.PendingConfirmation
	case .Ready: return snap,.Ready
	case: return {},.IntegrityFault
	}
}

// Recovery can finish an already pledged event. It never returns a live directory handle.
@(private)
recover_intake :: proc(w: store.VerifiedWriter,s: ^client.Session,root: e.Checkpoint,snap: IntakeSnapshot,
                       parent: l.Fd,entry: string,listed: bool,deadline: i64) -> IntakeOutcome {
	if !listed { return .DirectoryHold }
	p := snap.pending.(e.Pledge)
	row := snap.rows[len(snap.rows)-1]
	proposal,err := a.decode_marker_proposal(row.bytes,s.store,1)
	marker := err==.None
	fd := l.Fd(-1)
	defer if fd>=0 { l.close(fd) }
	if marker {
		if entry!=string(hex.encode(proposal.directory[:])) { return .DirectoryHold }
		ok: bool
		fd,ok = attempt_dir(parent,&proposal,false)
		if !ok { return .DirectoryHold }
	} else if snap.tail_import==nil {
		if _,te := a.decode_task_created(row.bytes,s.store,1); te!=.None { return .PendingConfirmation }
	}
	if !client.within_budget(s,2*u64(len(snap.rows))) { return .RecoveryLimitExceeded }
	segments := [?]r.Segment{{rows=snap.rows}}
	candidate := r.project_markers(root,{s.store,1,p.sequence,p.head},nil,segments[:],snap.receipts[:])
	if candidate.error!=.None { return .IntegrityFault }
	if snap.tail_import==nil && (len(candidate.tasks)!=1 || candidate.tasks[0].marker!=marker) { return .IntegrityFault }
	if !store.confirm_stored(w,s,p,snap.tail_import,deadline,marker=marker) { return .AttestationUncertain }
	return .RecoveredConfirmation
}

@(private)
intake_locked :: proc(w: store.VerifiedWriter,s: ^client.Session,root: e.Checkpoint,parent: l.Fd,payload: []u8,deadline: i64) -> (PreparedProposal,IntakeOutcome) {
	entry,listed := attempt_entry(parent)
	snap,status := intake_snapshot(w,s,root)
	if status==.PendingConfirmation { return {},recover_intake(w,s,root,snap,parent,entry,listed,deadline) }
	if status!=.Ready { return {},status }
	if len(snap.replay.tasks)>0 {
		if len(snap.replay.tasks)!=1 || !snap.replay.tasks[0].marker { return {},.ExistingTask }
		row := snap.rows[len(snap.rows)-1]
		proposal,err := a.decode_marker_proposal(row.bytes,s.store,1)
		if err!=.None || !listed || entry!=string(hex.encode(proposal.directory[:])) { return {},.DirectoryHold }
		fd,ok := attempt_dir(parent,&proposal,false)
		if !ok { return {},.DirectoryHold }
		l.close(fd)
		return {},.AlreadyProposed
	}
	if !listed || entry!="" { return {},.DirectoryHold }
	if snap.replay.receipts_used<len(snap.receipts) {
		ref: e.EventRef
		if reconcile_locked(w,s,nil,nil,&ref)!=.Ready { return {},.Unavailable }
		snap,status = intake_snapshot(w,s,root)
		if status!=.Ready || len(snap.replay.tasks)!=0 || snap.replay.receipts_used!=len(snap.receipts) { return {},.Unavailable }
	}
	if !client.within_budget(s) { return {},.RecoveryLimitExceeded }
	if snap.cp.sequence>=max(e.Sequence)-1 { return {},.IntegrityFault }
	ids: [7][16]u8
	for &id,i in ids {
		n,err := l.getrandom(id[:],{})
		if err!=.NONE || n!=16 || id==([16]u8{}) { return {},.Unavailable }
		for earlier in ids[:i] { if earlier==id { return {},.Unavailable } }
	}
	stamp := client.wb_recorded_us()
	if stamp<0 { return {},.Unavailable }
	task := a.TaskCreated{reference={s.store,1,snap.cp.sequence+1},recorded_time=u64(stamp),previous_head=snap.cp.head,
	                      task=e.TaskId(ids[0]),run=e.RunId(ids[1]),command=e.CommandId(ids[2]),evidence=e.EvidenceId(ids[3])}
	hash: sha2.Context_256
	sha2.init_256(&hash)
	sha2.update(&hash,transmute([]u8)string("warband.task.v1\x00"))
	for &id in ids[:3] { sha2.update(&hash,id[:]) }
	sha2.final(&hash,task.input_digest[:])
	proposal := a.MarkerProposal{task=task.task,run=task.run,proposal=e.ProposalId(ids[4]),attempt=e.AttemptId(ids[5]),
	                             directory=a.DirectoryId(ids[6]),length=u32(len(payload)),expected_task_version=1}
	copy(proposal.payload[:],payload)
	now := client.wb_elapsed_ms()
	if now<deadline-30_000 || now>=deadline { return {},.OperationDeadlineExceeded }
	fd,opened := attempt_dir(parent,&proposal,true)
	if !opened { return {},.DirectoryHold }
	transfer := false
	defer if !transfer { l.close(fd) }
	cp,confirmed := store.append_intake(w,s,snap.cp,snap.mark,task,deadline)
	if !confirmed { return {},.AttestationUncertain }
	stamp = client.wb_recorded_us()
	if stamp<0 { return {},.Unavailable }
	proposal.reference,proposal.previous_head,proposal.recorded_time = {s.store,1,cp.sequence+1},cp.head,u64(stamp)
	cp,confirmed = store.append_intake(w,s,cp,snap.mark,proposal,deadline)
	if !confirmed { return {},.AttestationUncertain }
	last,outcome := intake_snapshot(w,s,root)
	if outcome!=.Ready { return {},outcome }
	if last.cp!=cp || len(last.replay.tasks)!=1 { return {},.IntegrityFault }
	view := last.replay.tasks[0]
	if !view.marker || view.task_version!=1 || view.control_revision!=0 || view.consumed || view.complete { return {},.IntegrityFault }
	persisted,de := a.decode_marker_proposal(last.rows[len(last.rows)-1].bytes,s.store,1)
	if de!=.None || persisted!=proposal { return {},.IntegrityFault }
	name := strings.clone_to_cstring(string(hex.encode(persisted.directory[:])))
	current: l.Stat
	if l.fstatat(parent,name,&current,{.SYMLINK_NOFOLLOW})!=.NONE || !l.S_ISDIR(current.mode) ||
	   u64(current.dev)!=persisted.device || u64(current.ino)!=persisted.inode { return {},.DirectoryHold }
	now = client.wb_elapsed_ms()
	if now<deadline-30_000 || now>=deadline { return {},.OperationDeadlineExceeded }
	transfer = true
	return {persisted,fd,view},.ConfirmedProposal
}

// The caller owns directory_fd on ConfirmedProposal only. No prior execution's descriptor is reconstructed.
marker_intake :: proc(payload: []u8,scratch: ^mem.Arena) -> (PreparedProposal,IntakeOutcome) {
	temp := mem.begin_arena_temp_memory(scratch)
	defer mem.end_arena_temp_memory(temp)
	context.allocator=mem.arena_allocator(scratch)
	if len(payload)>a.MarkerPayloadLimit { return {},.Unavailable }
	root,uid,trusted := intake_configuration()
	if !trusted || !store.limit_sqlite() { return {},.Unavailable }
	start := client.wb_elapsed_ms()
	if start<0 { return {},.Unavailable }
	session := client.Session{path="endpoints/runtime.sock",uid=uid,store=root.store,epoch=1,deadline=start+60_000}
	gate := client.wb_writer_gate(IntakeDB)
	if gate<0 { return {},.LockUnavailable }
	defer client.wb_release_gate(gate)
	locked := client.wb_elapsed_ms()
	if locked<start || locked-start>=5_000 { return {},.LockUnavailable }
	parent,pe := l.open("attempts",DirectoryFlags)
	if pe!=.NONE { return {},.DirectoryHold }
	defer l.close(parent)
	if _,ok := private_dir(parent); !ok { return {},.DirectoryHold }
	w,err := store.open_writer(IntakeDB)
	if err!=.None { return {},.Unavailable }
	if !store.limit_writer_cache(w) { _=store.close_writer(&w); return {},.Unavailable }
	result,status := intake_locked(w,&session,root,parent,payload,start+30_000)
	closed := store.close_writer(&w)
	if !closed || session.exhausted {
		if status==.ConfirmedProposal { l.close(result.directory_fd) }
		if session.exhausted { return {},.RecoveryLimitExceeded }
		return {},.Unavailable
	}
	return result,status
}
