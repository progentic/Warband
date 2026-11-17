package custody_test

import "core:testing"
import "../../../src/custody"

@(test)
peer_role_requires_observed_uid_on_the_correct_listener :: proc(t: ^testing.T) {
	operators := [?]u64{2002, 2003}
	config := custody.PeerConfiguration{runtime_listener = 1, admin_listener = 2, runtime_uid = 1001, operator_uids = operators[:]}
	cases := [?]struct{listener, uid: u64, op: custody.Operation, role: custody.PeerRole}{
		{1, 1001, .Prepare, .Runtime}, {1, 1001, .Confirm, .Runtime}, {1, 1001, .Verify, .Runtime},
		{2, 2002, .Enroll, .Operator}, {2, 2003, .EpochChange, .Operator},
		{2, 1001, .Enroll, .Denied}, {2, 1001, .EpochChange, .Denied},
		{1, 1001, .Enroll, .Denied}, {1, 2002, .Enroll, .Denied}, {2, 2002, .Verify, .Denied},
		{1, 2002, .Verify, .Denied}, {1, 999, .Verify, .Denied}, {2, 999, .Enroll, .Denied},
		{3, 1001, .Verify, .Denied}, {1, 1001, custody.Operation(0), .Denied},
	}
	for c in cases {
		testing.expect_value(t, custody.decide_peer_role(config, c.listener, c.uid, c.op), c.role)
	}
	testing.expect_value(t, custody.decide_peer_role(config, 1, nil, .Verify), .Denied)
	config.admin_listener = config.runtime_listener
	testing.expect_value(t, custody.decide_peer_role(config, 1, u64(1001), .Verify), .Denied)
	config.admin_listener = 2
	operators[1] = config.runtime_uid
	testing.expect_value(t, custody.decide_peer_role(config, 2, u64(2002), .Enroll), .Denied)
	testing.expect_value(t, custody.decide_peer_role(config, 1, u64(1001), .Verify), .Denied)
}
