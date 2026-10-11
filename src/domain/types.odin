package domain

TaskId :: distinct u64
RunId :: distinct u64
Tick :: distinct u64
SchemaVersion :: distinct u8

FixtureSchema :: SchemaVersion(1)

Error :: enum {
	None,
	UnsupportedSchema,
	EmptyIdentifier,
	InvalidLength,
}

Fixture :: struct {
	schema: SchemaVersion,
	task:   TaskId,
	run:    RunId,
	tick:   Tick,
}

validate_fixture :: proc(value: Fixture) -> Error {
	if value.schema != FixtureSchema {
		return .UnsupportedSchema
	}
	if has_zero_pair(u64(value.task), u64(value.run)) {
		return .EmptyIdentifier
	}
	return .None
}

@(private)
has_zero_pair :: proc(first, second: u64) -> bool {
	return first == 0 || second == 0
}
