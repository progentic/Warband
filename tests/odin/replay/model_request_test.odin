package replay_test

import "core:encoding/hex"
import "core:testing"
import "core:reflect"
import a "../../../src/audit"
import c "../../../src/custody"
import e "../../../src/domain/events"
import m "../../../src/model"
import r "../../../src/replay"

IssuedVector :: "574245560200120001010101010101010101010101010101010000000000000001000000000000000a0000000000000009000100680000000202020202020202020202020202020203030303030303030303030303030303040404040404040404040404040404040100000002000000ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ade80300000000000018790000000000005555555555555555555555555555555555555555555555555555555555555555"
ExpiredVector :: "574245560200130001010101010101010101010101010101010000000000000002000000000000000b00000000000000090001003100000001010101010101010101010101010101010000000000000001000000000000000202020202020202020202020202020201bbd96add826fe7131d4e285561b0c1ecb9e1561237f99a3b817c8143846d5605"
ExpiryHead :: "5dcf7362ed36e3ceed328bfb6117a5a99366e1358fb87fcab1be33a264113f16"

@(test)
request_catalog_revision_and_uniqueness :: proc(t: ^testing.T) {
	entries := m.CatalogV1
	testing.expect(t,m.valid_catalog(entries[:]))
	for item in entries {
		stored,ok := m.catalog_entry(1,item.id)
		testing.expect(t,ok && item==stored)
	}
	_,ok := m.catalog_entry(2,1)
	testing.expect(t,!ok)
	entries[1].payload = entries[0].payload
	testing.expect(t,!m.valid_catalog(entries[:]))
	entries = m.CatalogV1
	entries[1].id = entries[0].id
	testing.expect(t,!m.valid_catalog(entries[:]))
}

@(test)
request_wire_and_confirmed_prefix :: proc(t: ^testing.T) {
	provider_observation_vectors(t)
	first,ok1 := hex.decode(transmute([]u8)string(IssuedVector)); defer delete(first)
	second,ok2 := hex.decode(transmute([]u8)string(ExpiredVector)); defer delete(second)
	assert(ok1 && ok2)
	store: e.StoreId
	for &x in store { x=1 }
	issue,ie := a.decode_request_issued(first,store,1)
	expiry,xe := a.decode_request_expired(second,store,1)
	testing.expect(t,ie==.None && xe==.None && issue.revision==1 && issue.catalog_id==2 &&
	               issue.payload_digest==m.catalog_digest("abc") && issue.start_ms==1000 &&
	               issue.deadline_ms==31000 && expiry.issuance==issue.reference && expiry.reason==.Deadline)
	encoded,err := a.encode_request_issued(issue,store,1)
	expired,err2 := a.encode_request_expired(expiry,store,1)
	testing.expect(t,err==.None && err2==.None && string(encoded[:])==string(first) && string(expired[:])==string(second))
	rows := [?]r.Row{{issue.reference,first},{expiry.reference,second}}
	segments := [?]r.Segment{{rows=rows[:]}}
	genesis := e.Checkpoint{store,1,0,issue.previous_head}
	cp := e.Checkpoint{store,1,1,expiry.previous_head}
	pledge := e.Pledge{store=store,epoch=1,previous_sequence=1,previous_head=cp.head,sequence=2,digest=fixture_digest(second[:105])}
	pledge.head = c.derive_head(pledge)
	head_text := hex.encode(pledge.head[:]); defer delete(head_text)
	testing.expect_value(t,string(head_text),string(ExpiryHead))
	pending,h := r.project_requests(genesis,cp,&pledge,segments[:],nil)
	defer delete(pending.tasks)
	testing.expect(t,pending.error==.None && pending.readiness==.PendingConfirmation && len(pending.tasks)==0 &&
	               h.count==1 && h.entries[0].issued==issue && h.entries[0].expiry==nil)
	cp = {store,1,2,pledge.head}
	done,history := r.project_requests(genesis,cp,nil,segments[:],nil)
	defer delete(done.tasks)
	testing.expect(t,done.error==.None && done.readiness==.Ready && len(done.tasks)==0 &&
	               history.count==1 && history.entries[0].expiry==expiry)
	old := r.project_markers(genesis,cp,nil,segments[:],nil)
	testing.expect(t,old.error!=.None)
	for offset in ([?]int{4,6,48,50,52}) {
		first[offset] ~= 1
		_,bad := a.decode_request_issued(first,store,1)
		testing.expect(t,bad!=.None)
		first[offset] ~= 1
	}
	for deadline in ([?]u64{issue.start_ms,issue.deadline_ms+1,max(u64)}) {
		mut := issue
		mut.deadline_ms = deadline
		_,bad := a.encode_request_issued(mut,store,1)
		testing.expect(t,bad!=.None)
	}
	second[104] = 0
	_,reason := a.decode_request_expired(second,store,1)
	testing.expect(t,reason==.Unsupported)
}

// Reseal fixture rows so semantic rejection cannot be attributed to a broken hash.
request_checkpoint :: proc(rows: []r.Row, genesis: e.Checkpoint) -> e.Checkpoint {
	cp := genesis
	for row in rows {
		b := row.bytes
		copy(b[len(b)-32:],cp.head[:])
		p := e.Pledge{store=cp.store,epoch=cp.epoch,sequence=row.ref.sequence,previous_head=cp.head,
		              digest=fixture_digest(b[:len(b)-32])}
		cp = {cp.store,cp.epoch,p.sequence,c.derive_head(p)}
	}
	return cp
}

@(test)
request_history_bounds_roles_and_versions :: proc(t: ^testing.T) {
	raw,ok := hex.decode(transmute([]u8)string(IssuedVector)); defer delete(raw)
	assert(ok)
	store: e.StoreId
	copy(store[:],raw[8:24])
	v,err := a.decode_request_issued(raw,store,1)
	assert(err==.None)
	genesis := e.Checkpoint{store,1,0,v.previous_head}
	rows: [33]r.Row
	data: [33]a.RequestIssuedBytes
	for &row,i in rows {
		v.reference.sequence = e.Sequence(i+1)
		v.id[0] = u8(i+1)
		wire,issue := a.encode_request_issued(v,store,1); assert(issue==.None)
		data[i] = wire
		row = {v.reference,data[i][:]}
	}
	for n in ([?]int{32,33}) {
		cp := request_checkpoint(rows[:n],genesis)
		segments := [?]r.Segment{{rows=rows[:n]}}
		view,h := r.project_requests(genesis,cp,nil,segments[:],nil)
		defer delete(view.tasks)
		if n==32 { testing.expect(t,view.error==.None && h.count==32) }
		else { testing.expect(t,view.error==.ResourceLimit && h.count==0) }
	}
	data[1][56] = data[0][56]
	cp := request_checkpoint(rows[:2],genesis)
	segments := [?]r.Segment{{rows=rows[:2]}}
	duplicate,h := r.project_requests(genesis,cp,nil,segments[:],nil)
	testing.expect(t,duplicate.error==.InvalidHistory && h.count==0)

	f := marker_fixture()
	rows[0].bytes = f.data[0][:f.lengths[0]+32] // TaskCreated, 1/0
	cp = request_checkpoint(rows[:2],genesis)
	task,with_request := r.project_requests(genesis,cp,nil,segments[:],nil)
	defer delete(task.tasks)
	testing.expect(t,task.error==.None && with_request.count==1 && len(task.tasks)==1 &&
	               task.tasks[0].task_version==1 && task.tasks[0].control_revision==0)
	x := a.RequestExpired{reference={store,1,3},issuance=rows[0].ref,id=with_request.entries[0].issued.id,reason=.Cancelled}
	wire,xe := a.encode_request_expired(x,store,1); assert(xe==.None)
	rows[2] = {x.reference,wire[:]}
	segments[0].rows=rows[:3]
	cp=request_checkpoint(rows[:3],genesis)
	wrong,empty := r.project_requests(genesis,cp,nil,segments[:],nil)
	testing.expect(t,wrong.error==.InvalidReference && empty.count==0)
}


// Independently packed little-endian normal-profile TlsFailure vector following IssuedVector.
ObservedVector :: "574245560200140001010101010101010101010101010101010000000000000002000000000000000b0000000000000009000100440000000101010101010101010101010101010101000000000000000100000000000000020202020202020202020202020202020202110100000000000000000000000000000000bbd96add826fe7131d4e285561b0c1ecb9e1561237f99a3b817c8143846d5605"
ObservedHead :: "8e900ad2b2d81c6489a499fb795cb8ea9cf5711628320dc6bd720c2c5a5e580c"

provider_observation_vectors :: proc(t:^testing.T) {
	// A new terminal reply in the model decoder must have a reviewed audit code.
	for val in m.ProviderFailure {
		name,_:=reflect.enum_name_from_value(val)
		_,transfer:=a.failure_code(.Transport,name)
		_,early:=a.failure_code(.Bare,name)
		testing.expect(t,transfer==(val!=.Spent))
		testing.expect(t,early==(val==.CredentialUnavailable || val==.Deadline || val==.Cancelled || val==.InvalidHandoff || val==.Spent))
	}
	for val in m.ProfileStatus {
		name,_:=reflect.enum_name_from_value(val)
		_,known:=a.failure_code(.Envelope,name)
		testing.expect(t,known==(val!=.Ok))
	}
	for val in m.Candidate_Rejection {
		name,_:=reflect.enum_name_from_value(val)
		_,known:=a.failure_code(.Candidate,name)
		testing.expect(t,known)
	}
	issue_bytes,ok:=hex.decode(transmute([]u8)string(IssuedVector)); assert(ok); defer delete(issue_bytes)
	golden,hex_ok:=hex.decode(transmute([]u8)string(ObservedVector)); assert(hex_ok); defer delete(golden)
	store:e.StoreId
	copy(store[:],issue_bytes[8:24])
	issue,ie:=a.decode_request_issued(issue_bytes,store,1); assert(ie==.None)
	v,err:=a.decode_provider_failure(golden,store,1); assert(err==.None)
	testing.expect(t,v.id==issue.id && v.issuance==issue.reference && v.failure.profile==.NormalConnectorV1 &&
	               v.failure.class==.Transport && v.failure.code==17 && v.failure.counts==a.FailureCounts{})
	wire,encoded:=a.encode_provider_failure(v,store,1)
	testing.expect(t,encoded==.None && string(wire[:])==string(golden))
	for mut in ([?]struct{offset:int,value:u8}{
		{104,0},{104,3},{105,0},{105,5},{106,0},{106,20},{107,0},{107,2},
		{108,99},{115,1},{119,1},{123,1},{6,19},{48,8},{52,0},
	}) {
		bad:=wire; bad[mut.offset]=mut.value
		_,invalid:=a.decode_provider_failure(bad[:],store,1)
		testing.expect(t,invalid!=.None)
	}
	bare:=v
	bare.failure={profile=.NormalConnectorV1,class=.Bare,code=1}
	b,be:=a.encode_provider_failure(bare,store,1); assert(be==.None)
	round,re:=a.decode_provider_failure(b[:],store,1)
	testing.expect(t,re==.None && round==bare && round.failure.counts==nil)
	b[108]=1
	_,padding:=a.decode_provider_failure(b[:],store,1)
	testing.expect_value(t,padding,a.Error.Malformed)
	bare.failure.counts=a.FailureCounts{}
	_,presence:=a.encode_provider_failure(bare,store,1)
	testing.expect_value(t,presence,a.Error.Malformed)
	v.failure.counts=a.FailureCounts{599,16384,16384,65536}
	limits,le:=a.encode_provider_failure(v,store,1)
	back,de:=a.decode_provider_failure(limits[:],store,1)
	testing.expect(t,le==.None && de==.None && v==back)
	rows:=[?]r.Row{{issue.reference,issue_bytes},{v.reference,wire[:]},{ {store,1,3},nil}}
	parts:=[1]r.Segment{{rows=rows[:2]}}
	genesis:=e.Checkpoint{store,1,0,issue.previous_head}
	cp:=request_checkpoint(rows[:2],genesis)
	head:=hex.encode(cp.head[:]); defer delete(head)
	testing.expect(t,string(head)==ObservedHead)
	before:=e.Checkpoint{store,1,1,v.previous_head}
	pledge:=e.Pledge{store=store,epoch=1,previous_sequence=1,previous_head=before.head,sequence=2,
	                 digest=fixture_digest(wire[:124]),head=cp.head}
	pending,prefix:=r.project_requests(genesis,before,&pledge,parts[:],nil)
	defer delete(pending.tasks)
	testing.expect(t,pending.error==.None && pending.readiness==.PendingConfirmation && prefix.count==1 &&
	               prefix.entries[0].failure==nil)
	view,h:=r.project_requests(genesis,cp,nil,parts[:],nil)
	defer delete(view.tasks)
	testing.expect(t,view.error==.None && len(view.tasks)==0 && h.count==1 && h.entries[0].expiry==nil &&
	               h.entries[0].failure==a.FailureDetails{.NormalConnectorV1,.Transport,17,a.FailureCounts{}})
	legacy:=r.project_markers(genesis,cp,nil,parts[:],nil)
	testing.expect(t,legacy.error!=.None)
	fixture:=wire; fixture[104]=1
	rows[1].bytes=fixture[:]
	changed,empty:=r.project_requests(genesis,cp,nil,parts[:],nil)
	testing.expect(t,changed.error!=.None && empty.count==0)
	cp=request_checkpoint(rows[:2],genesis)
	alternate,other:=r.project_requests(genesis,cp,nil,parts[:],nil)
	defer delete(alternate.tasks)
	failure,seen:=other.entries[0].failure.(a.FailureDetails)
	testing.expect(t,alternate.error==.None && seen && failure.profile==.FixtureConnectorV1)
	copy3:=wire
	copy3[32]=3
	rows[2].bytes=copy3[:]
	parts[0].rows=rows[:]
	cp=request_checkpoint(rows[:],genesis) // resealed conflicting duplicate, not a hash mismatch
	duplicate,dropped:=r.project_requests(genesis,cp,nil,parts[:],nil)
	testing.expect(t,duplicate.error==.InvalidHistory && dropped.count==0)
	parts[0].rows=rows[:2]
	fixture[88] ~= 1
	cp=request_checkpoint(rows[:2],genesis)
	mismatch,missing:=r.project_requests(genesis,cp,nil,parts[:],nil)
	testing.expect(t,mismatch.error==.InvalidReference && missing.count==0)
}
