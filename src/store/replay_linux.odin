package store

import a "../audit"
import r "../replay"
import e "../domain/events"
import client "../runtime/client"

// SQLite owns column memory until the next step. Copy bounded canonical bytes
// while the read transaction and statement are alive. Caller's arena owns copies.
read_replay_segment :: proc(path: cstring, scope: e.EventRef, session: ^client.Session, live_cp: Maybe(e.Checkpoint)) -> ([]r.Row,Maybe(r.Projection),bool) {
	db: Database
	rc := sqlite3_open_v2(path,&db,1,nil)
	defer if db!=nil { sqlite3_close(db) }
	if rc!=0 || sqlite3_db_readonly(db,"main")!=1 { return nil,nil,false }
	state := WriterState{db=db}
	if !configure_cache(&state) || !change(db,"BEGIN") || read_scalar(&state,"PRAGMA user_version")!=i64(1) { return nil,nil,false }
	count,ok := read_scalar(&state,"SELECT count(*) FROM events").(i64)
	// Reserve one extraction, one integrity pass and one semantic pass per row.
	if !ok || count<0 || count>100_000 || !client.within_budget(session,3*u64(count)) { return nil,nil,false }
	rows,err := make([]r.Row,int(count),context.allocator)
	if err!=nil { return nil,nil,false }
	epoch := word(u64(scope.epoch))
	scope := scope
	for &row,i in rows {
		seq := word(u64(i+1))
		stmt,prepared := bound(db,"SELECT canonical_event FROM events WHERE store_id=? AND epoch=? AND sequence=?",scope.store[:],epoch[:],seq[:])
		if !prepared { return nil,nil,false }
		defer sqlite3_finalize(stmt)
		if sqlite3_step(stmt)!=ROW || !client.within_budget(session) { return nil,nil,false }
		bytes := column(stmt,0)
		if len(bytes)<88 || len(bytes)>65536+88 { return nil,nil,false }
		data,alloc := make([]u8,len(bytes),context.allocator)
		if alloc!=nil { return nil,nil,false }
		copy(data,bytes)
		row = {{scope.store,scope.epoch,e.Sequence(i+1)},data}
	}
	when #config(WARBAND_REPLAY_LIVE_COMPARE,false) {
		if cp,present := live_cp.(e.Checkpoint); present {
			h := NoopHistory{acceptance_scan=true}
			imports: [dynamic]Import
			defer delete(imports)
			seg,valid := inspect_segment(&state,cp,nil,&imports,session,&h)
			if valid && seg.journal==cp && mark_matches(&state,cp.store,seg.last_import) && h.task!=nil && !h.terminal {
				return rows,live_projection(h),true
			}
		}
	}
	return rows,nil,true
}

@(private)
live_projection :: proc(h: NoopHistory) -> r.Projection {
	task := h.task.(a.TaskCreated)
	p := r.Projection{store=task.reference.store,epoch=task.reference.epoch,key={task.task,task.run},
		task_version=h.task_version,control_revision=h.control_revision,complete=h.transition!=nil,revoked=h.revoked}
	if permit,ok := h.permit.(a.AuthorizationRecorded); ok { p.authorization=u8(permit.decision) }
	if claim,ok := h.claim.(a.DispatchClaimed); ok { p.attempt=claim.attempt; p.consumed=true }
	if obs,ok := h.observation.(a.ObservationRecorded); ok { p.observation=u8(obs.outcome) }
	if ev,ok := h.evaluation.(a.EvaluationRecorded); ok { p.verdict=u8(ev.verdict) }
	return p
}
