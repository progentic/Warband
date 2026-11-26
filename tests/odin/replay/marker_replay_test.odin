package replay_test

import "core:testing"
import r "../../../src/replay"

@(test)
marker_confirmed_prefix_projection :: proc(t: ^testing.T) {
	f := marker_fixture()
	control := [8]u64{0,0,0,1,2,2,2,3}
	for n in 1..=8 {
		actual := fixture_project(&f,n,check_final=n==8)
		defer delete(actual.tasks)
		again := fixture_project(&f,n)
		defer delete(again.tasks)
		testing.expect(t,actual.error==.None && actual.readiness==.Ready && len(actual.tasks)==1)
		if len(actual.tasks)!=1 || len(again.tasks)!=1 { testing.expect(t,false); return }
		p := actual.tasks[0]
		testing.expect(t,again.error==.None && again.readiness==.Ready && again.tasks[0]==p && actual.receipts_used==0)
		testing.expect(t,p.epoch==1 && string(p.store[:])==string(f.data[0][8:24]) && string(p.key.task[:])==string(f.data[0][56:72]) && string(p.key.run[:])==string(f.data[0][72:88]))
		if n>=5 { testing.expect(t,string(p.attempt[:])==string(f.data[4][88:104])) }
		testing.expect(t,p.task_version==(2 if n==8 else 1) && p.control_revision==control[n-1])
		testing.expect(t,p.marker==(n>=2) && u8(p.approval)==u8(n>=3) && p.authorization==u8(n>=4))
		testing.expect(t,p.consumed==(n>=5) && p.complete==(n==8) && !p.revoked)
		testing.expect(t,p.observation==(2 if n>=6 else 0) && u8(p.delivery)==(2 if n>=6 else 0) && p.verdict==u8(n>=7))
		if n==1 {
			legacy := fixture_project(&f,n,legacy=true); defer delete(legacy.tasks)
			testing.expect(t,legacy.error==.None && len(legacy.tasks)==1 && legacy.tasks[0]==p)
		}
	}
	tail := fixture_project(&f,8,pending_tail=true); defer delete(tail.tasks)
	testing.expect(t,tail.error==.None && tail.readiness==.PendingConfirmation && len(tail.tasks)==1)
	if len(tail.tasks)==1 {
		p := tail.tasks[0]
		testing.expect(t,!p.complete && p.consumed && p.verdict==1 && p.task_version==1 && p.control_revision==2)
	}
	for legacy in ([?]bool{true,false}) {
		bad := fixture_project(&f,8,legacy=legacy,wrong_root=!legacy)
		defer delete(bad.tasks)
		testing.expect(t,bad.error==.IntegrityFault && bad.tasks==nil)
	}
}

expect_invalid :: proc(t: ^testing.T,f: ^MarkerFixture,n: int,issue: r.Error) {
	result := fixture_project(f,n)
	defer delete(result.tasks)
	testing.expect_value(t,result.error,issue)
	testing.expect(t,result.readiness==.IntegrityFault && result.tasks==nil)
}

@(test)
marker_verdict_from_observed_binding :: proc(t: ^testing.T) {
	// entry, stopped, control, length, expected verdict, approved payload is empty
	Case :: struct {entry,stopped,control,length,verdict: u8, empty: bool}
	cases := [?]Case{{2,1,1,0,1,true},{1,1,1,0,2,true},{1,1,1,0,2,false},
	                 {2,1,1,3,3,false},{2,1,1,2,3,false},{0,0,1,0,3,false},{0,1,0,0,3,false},
	                 {3,1,1,0,3,false},{4,1,1,1,3,false},{5,1,1,0,3,false}}
	for v in cases {
		f := marker_fixture()
		if v.empty {
			set_body(&f,1,EmptyBody2); set_body(&f,2,EmptyBody3)
			set_body(&f,4,EmptyBody5); set_body(&f,5,EmptyBody6)
		}
		f.data[5][105],f.data[5][106],f.data[5][107],f.data[5][108] = v.stopped,v.control,v.entry,v.length
		if v.entry==4 { f.data[5][109]=16 } // 4097 bytes; no file digest
		if v.entry!=2 { for &b in f.data[5][116:148] { b=0 } }
		if v.entry==2 && v.length==3 { f.data[5][116] ~= 1 }
		sync_observation_digest(&f)
		f.data[6][154]=v.verdict
		n := 8 if v.verdict==1 else 7
		result := fixture_project(&f,n); defer delete(result.tasks)
		testing.expect(t,result.error==.None && len(result.tasks)==1 && result.tasks[0].verdict==v.verdict &&
		                 result.tasks[0].complete==(v.verdict==1))
		if v.verdict!=1 { expect_invalid(t,&f,8,.InvalidHistory) }
		f.data[6][154] = 3 if v.verdict==1 else 1
		expect_invalid(t,&f,7,.InvalidHistory)
	}
}

@(test)
marker_role_order_and_uniqueness :: proc(t: ^testing.T) {
	Mutation :: struct {row,offset: int, value: u8, issue: r.Error}
	cases := [?]Mutation{{2,80,1,.InvalidReference},{3,80,2,.InvalidReference},{2,164,2,.InvalidHistory},
	                     {2,88,0,.InvalidHistory},{2,120,4,.InvalidHistory},{2,124,0,.InvalidHistory},{3,104,1,.InvalidHistory},{4,136,0,.InvalidHistory},
	                     {4,88,0,.InvalidHistory},{6,120,0,.InvalidHistory},{7,112,4,.InvalidReference},
	                     {7,144,3,.InvalidHistory}}
	for v in cases {
		f := marker_fixture()
		f.data[v.row][v.offset]=v.value
		expect_invalid(t,&f,8,v.issue)
	}
	for i in 2..=7 {
		f := marker_fixture()
		f.data[i+1],f.lengths[i+1] = f.data[i],f.lengths[i]
		expect_invalid(t,&f,i+2,.InvalidHistory)
	}
	for control in ([?]string{RevocationBody,DispositionBody}) {
		f := marker_fixture()
		f.data[8],f.lengths[8] = f.data[7],f.lengths[7]
		set_body(&f,7,control)
		result := fixture_project(&f,8); defer delete(result.tasks)
		testing.expect(t,result.error==.None && len(result.tasks)==1 && result.tasks[0].control_revision==3)
		if len(result.tasks)==1 {
			testing.expect(t,result.tasks[0].revoked==(control==RevocationBody) && (result.tasks[0].disposition!=0)==(control==DispositionBody))
		}
		f.data[8][144]=3
		expect_invalid(t,&f,9,.InvalidHistory)
	}
	f := marker_fixture()
	set_body(&f,1,NoopProposal); set_body(&f,2,NoopPermit)
	old := fixture_project(&f,3,legacy=true); defer delete(old.tasks)
	both := fixture_project(&f,3); defer delete(both.tasks)
	testing.expect(t,old.error==.None && both.error==.None && len(both.tasks)==1 && both.tasks[0]==old.tasks[0])
	f.data[3],f.lengths[3] = f.data[4],f.lengths[4]
	f.data[3][80]=3 // MarkerClaim cites the v1 permit
	expect_invalid(t,&f,4,.InvalidReference)
	f = marker_fixture()
	// A structurally valid v1 DispatchClaimed (including its extra claim time) cites a marker permit.
	f.data[4][4],f.data[4][6],f.data[4][52] = 1,4,120
	f.lengths[4] += 8
	expect_invalid(t,&f,5,.InvalidReference)
}
