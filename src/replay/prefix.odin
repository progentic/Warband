package replay

import a "../audit"
import c "../custody"
import e "../domain/events"
import "core:crypto/sha2"
import "core:encoding/endian"

Row :: struct {ref: e.EventRef, bytes: []u8}
Error :: enum {None, IntegrityFault, InvalidReference, InvalidHistory, ResourceLimit}
Key :: struct {task: e.TaskId, run: e.RunId}
Projection :: struct {
	store: e.StoreId, epoch: e.Epoch, key: Key,
	task_version, control_revision: u64,
	complete, consumed, revoked: bool,
	authorization, observation, verdict, disposition: u8, // marker observation class zero may mean Unassessed
	disposition_reason: u16,
	attempt: e.AttemptId,
	marker: bool,
	approval: a.MarkerDecision,
	delivery: a.MarkerDelivery, // zero until an observation exists, including Unassessed
}
Result :: struct {error: Error, readiness: e.RecoveryDecision, tasks: [dynamic]Projection, receipts_used: int}
@(private)
Event :: union {a.TaskCreated,a.ProposalRecorded,a.AuthorizationRecorded,a.DispatchClaimed,a.ObservationRecorded,
                a.EvaluationRecorded,a.TransitionAccepted,a.RejectionRecorded,a.CapabilityRevoked,a.AttemptDisposition,
                a.RequestIssued,a.RequestExpired,a.ProviderFailureObserved,MarkerProposalSummary,MarkerApprovalSummary,a.MarkerPermit,a.MarkerClaim,a.MarkerObservation,a.MarkerEvaluation,a.MarkerAccepted}
@(private)
Record :: struct {event: Event, digest: [32]u8}
// Qualified Phase 2 sizes on both 64-bit targets. Never store a marker payload per row.
when size_of(int)==8 { #assert(size_of(Record)==232 && size_of(Projection)==104) }

@(private)
decode :: proc(b: []u8,ref: e.EventRef, $markers: bool, requests: bool) -> (Event,bool) {
	kind,_ := endian.get_u16(b[6:8],.Little)
	when markers {
		if requests && kind==18 {
			v,err := a.decode_request_issued(b,ref.store,ref.epoch)
			return v,err==.None && v.reference==ref
		}
		if requests && kind==19 {
			v,err := a.decode_request_expired(b,ref.store,ref.epoch)
			return v,err==.None && v.reference==ref
		}
		if requests && kind==20 {
			v,err := a.decode_provider_failure(b,ref.store,ref.epoch)
			return v,err==.None && v.reference==ref
		}
		if kind >= 11 { return decode_marker(b,ref,kind) }
	}
	switch kind {
	case 1:
		v,err := a.decode_task_created(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 2:
		v,err := a.decode_proposal_recorded(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 3:
		v,err := a.decode_authorization_recorded(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 4:
		v,err := a.decode_dispatch_claimed(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 5:
		v,err := a.decode_observation_recorded(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 6:
		v,err := a.decode_evaluation_recorded(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 7:
		v,err := a.decode_transition_accepted(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 8:
		v,err := a.decode_rejection_recorded(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 9:
		v,err := a.decode_capability_revoked(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	case 10:
		v,err := a.decode_attempt_disposition(b,ref.store,ref.epoch)
		return v,err==.None && v.reference==ref
	}
	return nil,false
}

@(private)
hash :: proc(domain: string,b: []u8) -> [32]u8 {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx,transmute([]u8)domain)
	sha2.update(&ctx,b)
	h: [32]u8
	sha2.final(&ctx,h[:])
	return h
}

Segment :: struct {rows: []Row, handoff: []u8} // original WBCR request opening the next epoch
Receipt :: struct {epoch: e.Epoch, digest: [32]u8}
@(private)
Validated :: struct {records: []Record, genesis: [32]u8, readiness: e.RecoveryDecision}

// Authenticate backward from the live checkpoint. Only after every segment has
// passed chain validation may the private reducer inspect confirmed events.
project :: proc(cp: e.Checkpoint,pending: ^e.Pledge,segments: []Segment,receipts: []Receipt) -> Result {
	return project_profile(cp,pending,segments,receipts,false)
}

// Bind the first segment to the authenticated enrollment and the last to the supplied live head.
project_markers :: proc(genesis,cp: e.Checkpoint,pending: ^e.Pledge,segments: []Segment,receipts: []Receipt) -> Result {
	return project_profile(cp,pending,segments,receipts,true,genesis)
}

// The older entry points deliberately reject request kinds, even in a pending tail.
project_requests :: proc(genesis,cp: e.Checkpoint,pending: ^e.Pledge,segments: []Segment,receipts: []Receipt) -> (Result,RequestHistory) {
	history: RequestHistory
	result := project_profile(cp,pending,segments,receipts,true,genesis,&history)
	if result.error!=.None { return result,{} }
	return result,history
}

@(private)
project_profile :: proc(cp: e.Checkpoint,pending: ^e.Pledge,segments: []Segment,receipts: []Receipt,$markers: bool,genesis: e.Checkpoint = {},requests: ^RequestHistory = nil) -> Result {
	bad := Result{error=.IntegrityFault,readiness=.IntegrityFault}
	if cp.store==(e.StoreId{}) || cp.epoch==0 || u64(len(segments))!=u64(cp.epoch) { return bad }
	valid,err := make([]Validated,len(segments),context.allocator)
	if err!=nil { return {error=.ResourceLimit} }
	defer { for v in valid { delete(v.records) }; delete(valid) }
	head := cp
	pledge := pending
	for i:=len(segments)-1; i>=0; i-=1 {
		variant,issue := validate(head,pledge,segments[i].rows,markers,requests!=nil)
		valid[i] = variant
		if issue!=.None { return {error=issue,readiness=variant.readiness} }
		if i==0 { break }
		wire := segments[i-1].handoff
		req,decode_err := c.decode_request(wire,cp.store,e.Epoch(i))
		if decode_err!=.None || req.operation!=.EpochChange || string(wire[91:123])!=string(variant.genesis[:]) { return bad }
		head = req.payload.(c.EpochRequest).old
		pledge = nil
	}
	when markers {
		if genesis.store!=cp.store || genesis.epoch!=1 || genesis.sequence!=0 || genesis.head!=valid[0].genesis { return bad }
	}
	used := 0
	tasks: [dynamic]Projection
	for v in valid {
		items,count,issue := reduce(v.records,receipts[used:],markers,requests)
		if issue!=.None { delete(tasks); return {error=issue,readiness=.IntegrityFault} }
		_,append_err := append(&tasks,..items)
		delete(items)
		if append_err!=nil { delete(tasks); return {error=.ResourceLimit} }
		used += count
	}
	return {.None,valid[len(valid)-1].readiness,tasks,used}
}

@(private)
validate :: proc(cp: e.Checkpoint,pending: ^e.Pledge,rows: []Row,$markers: bool,requests: bool) -> (Validated,Error) {
	bad := Validated{readiness=.IntegrityFault}
	if u64(cp.sequence)>u64(len(rows)) { return bad,.IntegrityFault }
	records,alloc := make([]Record,int(cp.sequence),context.allocator)
	if alloc!=nil { return bad,.ResourceLimit }
	keep := false
	defer if !keep { delete(records) }
	genesis := cp.head
	journal := cp
	journal.sequence = 0
	last: e.Pledge
	for row,i in rows {
		ref := e.EventRef{cp.store,cp.epoch,e.Sequence(i+1)}
		b := row.bytes
		if row.ref!=ref || len(b)<88 { return bad,.IntegrityFault }
		event,valid := decode(b,ref,markers,requests)
		if !valid { return bad,.IntegrityFault }
		last = {store=ref.store,epoch=ref.epoch,sequence=ref.sequence,previous_sequence=journal.sequence,
		        digest=hash(a.EventDomain,b[:len(b)-32])}
		copy(last.previous_head[:],b[len(b)-32:])
		if i==0 { genesis=last.previous_head }
		if (i>0 || cp.sequence==0) && last.previous_head!=journal.head { return bad,.IntegrityFault }
		last.head = c.derive_head(last)
		journal = {ref.store,ref.epoch,ref.sequence,last.head}
		if ref.sequence==cp.sequence && journal!=cp { return bad,.IntegrityFault }
		if i<len(records) { records[i] = {event,last.digest} }
	}
	tail: ^e.Pledge
	if journal.sequence>cp.sequence { tail = &last }
	ready := e.classify_recovery(cp,journal,pending,tail)
	switch ready {
	case .Ready,.PendingConfirmation,.PendingEventMissing:
	case .UnattestedTail,.IntegrityFault,.StoreIdentityMismatch,.EpochMismatch:
		return {readiness=ready},.IntegrityFault
	}
	keep = true
	return {records,genesis,ready},.None
}
