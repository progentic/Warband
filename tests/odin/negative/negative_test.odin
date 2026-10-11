package negative_test

import "core:testing"
import "../../../src/domain"
import "../../../src/fixture"

@(test)
unknown_fixture_schema_is_rejected :: proc(t: ^testing.T) {
	value := domain.Fixture{schema = 255, task = 1, run = 2, tick = 3}
	bytes := fixture.encode(value)
	decoded, err := fixture.decode(bytes[:])
	testing.expect_value(t, err, .None)
	testing.expect_value(t, domain.validate_fixture(decoded), .UnsupportedSchema)
}

@(test)
empty_identifiers_are_rejected :: proc(t: ^testing.T) {
	value := domain.Fixture{schema = domain.FixtureSchema, run = 2}
	testing.expect_value(t, domain.validate_fixture(value), .EmptyIdentifier)
	value.task = 1
	value.run = 0
	testing.expect_value(t, domain.validate_fixture(value), .EmptyIdentifier)
}

@(test)
truncated_and_oversized_bytes_are_rejected :: proc(t: ^testing.T) {
	bytes: [fixture.ByteCount + 1]u8
	_, short_error := fixture.decode(bytes[:fixture.ByteCount - 1])
	_, long_error := fixture.decode(bytes[:])
	testing.expect_value(t, short_error, .InvalidLength)
	testing.expect_value(t, long_error, .InvalidLength)
}
