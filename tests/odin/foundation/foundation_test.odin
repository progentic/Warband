package foundation_test

import "core:testing"
import "../../../src/domain"
import "../../../src/fixture"

// These identities must remain distinct at compile time.
#assert(domain.TaskId != domain.RunId)
#assert(domain.TaskId != domain.Tick)

@(test)
fixture_has_exact_portable_bytes :: proc(t: ^testing.T) {
	// Independent field layout: docs/verification/phase1-fixture-specification.md.
	// Expected bytes stay literal; they are never computed by the encoder.
	value := domain.Fixture{schema = domain.FixtureSchema, task = 0x0102030405060708, run = 2, tick = 3}
	actual := fixture.encode(value)
	expected := fixture.Encoded{1, 8, 7, 6, 5, 4, 3, 2, 1, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0}
	testing.expect_value(t, actual, expected)
}

@(test)
fixture_round_trip_preserves_injected_values :: proc(t: ^testing.T) {
	value := domain.Fixture{schema = domain.FixtureSchema, task = 27, run = 42, tick = 12345}
	bytes := fixture.encode(value)
	decoded, err := fixture.decode(bytes[:])
	testing.expect_value(t, err, .None)
	testing.expect_value(t, decoded, value)
}
