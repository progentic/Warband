package custody

// Listener IDs identify the actual bound endpoints; configuration validation
// must resolve them before supplying them here. Peer UID comes from the OS.
PeerConfiguration :: struct {
	runtime_listener, admin_listener: u64,
	runtime_uid: u64,
	operator_uids: []u64,
}
PeerRole :: enum {Denied, Runtime, Operator}

decide_peer_role :: proc(config: PeerConfiguration, listener: u64, peer_uid: Maybe(u64), operation: Operation) -> PeerRole {
	uid, observed := peer_uid.(u64)
	if !observed || config.runtime_listener == config.admin_listener {
		return .Denied
	}
	is_operator := false
	for operator in config.operator_uids {
		if operator == config.runtime_uid {
			return .Denied
		}
		if operator == uid {
			is_operator = true
		}
	}
	switch operation {
	case .Prepare, .Confirm, .Verify:
		if listener == config.runtime_listener && uid == config.runtime_uid {
			return .Runtime
		}
	case .Enroll, .EpochChange:
		if listener == config.admin_listener && is_operator {
			return .Operator
		}
	}
	return .Denied
}
