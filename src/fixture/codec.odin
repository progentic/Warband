package fixture

import "../domain"
import "core:encoding/endian"

ByteCount :: 25
TaskStart :: 1
RunStart :: 9
TickStart :: 17
Encoded :: [ByteCount]u8

// This fixed fixture format is not an event-store serialization decision.
encode :: proc(value: domain.Fixture) -> Encoded {
	bytes: Encoded
	bytes[0] = u8(value.schema)
	write_word(bytes[TaskStart:RunStart], u64(value.task))
	write_word(bytes[RunStart:TickStart], u64(value.run))
	write_word(bytes[TickStart:], u64(value.tick))
	return bytes
}

decode :: proc(bytes: []u8) -> (domain.Fixture, domain.Error) {
	if len(bytes) != ByteCount {
		return {}, .InvalidLength
	}
	value := domain.Fixture{
		schema = domain.SchemaVersion(bytes[0]),
		task = domain.TaskId(read_word(bytes[TaskStart:RunStart])),
		run = domain.RunId(read_word(bytes[RunStart:TickStart])),
		tick = domain.Tick(read_word(bytes[TickStart:])),
	}
	return value, .None
}

write_word :: proc(bytes: []u8, value: u64) {
	assert(endian.put_u64(bytes, .Little, value))
}

read_word :: proc(bytes: []u8) -> u64 {
	value, ok := endian.get_u64(bytes, .Little)
	assert(ok)
	return value
}
