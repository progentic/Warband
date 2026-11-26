package replay_test

import "core:testing"
import "core:encoding/hex"
import r "../../../src/replay"
import e "../../../src/domain/events"
import a "../../../src/audit"
import c "../../../src/custody"

FirstTaskHex :: "5742455601000100010101010101010101010101010101010100000000000000010000000000000000000000000000000100010060000000111111111111111111111111111111112222222222222222222222222222222233333333333333333333333333333333f391748065ca713ac26dcf0269d966c41f4fcb898302daa5b9fb1a3a7186295f555555555555555555555555555555554108f68b6628686c9fe94edc2de4870eeff827522ac180a58721a75bc097cd18"

// The published first TaskCreated would create a task if an unconfirmed tail leaked.
@(test)
confirmed_prefix_and_readiness :: proc(t: ^testing.T) {
	encoded := FirstTaskHex
	b,ok := hex.decode(transmute([]u8)encoded)
	defer delete(b)
	testing.expect(t,ok)
	cp := e.Checkpoint{epoch=1}
	copy(cp.store[:],b[8:24])
	copy(cp.head[:],b[len(b)-32:])
	value,err := a.decode_task_created(b,cp.store,1)
	testing.expect_value(t,err,.None)
	digest,_ := a.digest_task_created(value,cp.store,1)
	p := e.Pledge{store=cp.store,epoch=1,sequence=1,previous_head=cp.head,digest=digest}
	p.head=c.derive_head(p)
	rows := [?]r.Row{{value.reference,b}}
	segments := [?]r.Segment{{rows=rows[:]}}
	result := r.project(cp,&p,segments[:],nil)
	defer delete(result.tasks)
	testing.expect_value(t,result.error,.None)
	testing.expect_value(t,result.readiness,.PendingConfirmation)
	testing.expect_value(t,len(result.tasks),0)
	extra := r.project(cp,nil,segments[:],nil)
	testing.expect_value(t,extra.readiness,.UnattestedTail)
	testing.expect(t,extra.tasks==nil)
	accepted := r.project({cp.store,1,1,p.head},nil,segments[:],nil)
	defer delete(accepted.tasks)
	testing.expect_value(t,accepted.error,.None)
	testing.expect_value(t,len(accepted.tasks),1)
	// The published epoch-change request authenticates this archived TaskCreated
	// through the next epoch's sequence-zero checkpoint.
	handoff_hex: string = "57424352010005a8000000010101010101010101010101010101010100000000000000010000000000000000e4744b1c88560ba1cda5b78aa10ebef46737bc03d493dc4d999211120fb72f02000000000000000000000000000000789be34508f45f8144db0001415d4653351e6117b10771660d7e5fa01974772c666666666666666666666666666666660600726f746174659f78c749249d443ce4e12d122cd0d402744530fabc94b26c2131a009c510a1f4"
	handoff,decoded := hex.decode(transmute([]u8)handoff_hex)
	defer delete(handoff)
	testing.expect(t,decoded)
	next := e.Checkpoint{store=cp.store,epoch=2}
	copy(next.head[:],handoff[91:123])
	epochs := [?]r.Segment{{rows=rows[:],handoff=handoff},{}}
	archived := r.project(next,nil,epochs[:],nil)
	defer delete(archived.tasks)
	testing.expect_value(t,archived.error,.None)
	testing.expect_value(t,len(archived.tasks),1)
	next.head[0] ~= 1
	substituted := r.project(next,nil,epochs[:],nil)
	testing.expect_value(t,substituted.error,.IntegrityFault)
	testing.expect(t,substituted.tasks==nil)
	segments[0].rows=nil
	missing := r.project(cp,&p,segments[:],nil)
	defer delete(missing.tasks)
	testing.expect_value(t,missing.readiness,.PendingEventMissing)
	testing.expect_value(t,missing.error,.None)
}

@(test)
short_prefix_withholds_every_projection :: proc(t: ^testing.T) {
	cp := e.Checkpoint{epoch=1,sequence=1}
	cp.store[0]=1
	segments := [?]r.Segment{{}}
	result := r.project(cp,nil,segments[:],nil)
	testing.expect_value(t,result.error,.IntegrityFault)
	testing.expect(t,result.tasks==nil)
}

@(test)
v1_projection_withholds_on_confirmed_marker :: proc(t: ^testing.T) {
	first,ok := hex.decode(transmute([]u8)string(FirstTaskHex))
	defer delete(first)
	testing.expect(t,ok)
	ref := e.EventRef{epoch=1,sequence=1}
	copy(ref.store[:],first[8:24])
	task,issue := a.decode_task_created(first,ref.store,1)
	testing.expect_value(t,issue,.None)
	digest,err := a.digest_task_created(task,ref.store,1)
	testing.expect_value(t,err,.None)
	link := e.Pledge{store=ref.store,epoch=1,sequence=1,previous_head=task.previous_head,digest=digest}
	head := c.derive_head(link)
	marker := a.MarkerProposal{reference={ref.store,1,2},task=task.task,run=task.run,
	                           expected_task_version=1,device=8,inode=9,previous_head=head}
	marker.proposal[0],marker.attempt[0],marker.directory[0] = 4,5,6
	wire,encoded := a.encode_marker_proposal(marker,ref.store,1)
	testing.expect_value(t,encoded,.None)
	bytes := wire.data[:wire.length]
	decoded,valid := a.decode_marker_proposal(bytes,ref.store,1)
	testing.expect(t,valid==.None && decoded==marker)
	rows := [?]r.Row{{ref,first},{marker.reference,bytes}}
	segments := [?]r.Segment{{rows=rows[:1]}}
	prefix := r.project({ref.store,1,1,head},nil,segments[:],nil)
	defer delete(prefix.tasks)
	testing.expect(t,prefix.error==.None && prefix.readiness==.Ready && len(prefix.tasks)==1)
	link.previous_sequence,link.sequence,link.previous_head = 1,2,head
	link.digest,err = a.digest_marker_proposal(decoded,ref.store,1)
	testing.expect_value(t,err,.None)
	segments[0].rows = rows[:]
	// Independently derived from the two wire bodies and their full Refs.
	expected_hex: string = "39e91dbd15d65738062997e0a609e69b8f2af8211988b8433a40bdaf661d2544"
	expected,parsed := hex.decode(transmute([]u8)expected_hex)
	defer delete(expected)
	mixed_head := c.derive_head(link)
	testing.expect(t,parsed && string(mixed_head[:])==string(expected))
	mixed := r.project({ref.store,1,2,mixed_head},nil,segments[:],nil)
	defer delete(mixed.tasks)
	testing.expect(t,mixed.error==.IntegrityFault && mixed.readiness==.IntegrityFault && mixed.tasks==nil)
}
