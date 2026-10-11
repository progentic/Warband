package main

import "core:fmt"
import "core:os"
import "../../src/domain"
import "../../src/fixture"

Command :: enum { Version, Fixture, Invalid }
VersionText :: "Warband Phase 1 foundation (no execution authority)"
UsageText :: "usage: warband version | fixture"
FailureStatus :: 2
RequiredArgumentCount :: 2
VersionCommand :: "version"
FixtureCommand :: "fixture"
BytePresentation :: "%02x\n"
FixtureTask :: domain.TaskId(1)
FixtureRun :: domain.RunId(2)
FixtureTick :: domain.Tick(3)

main :: proc() {
	arguments := read_arguments()
	command := parse_command(arguments)
	run_command(command)
}

run_command :: proc(command: Command) {
	switch command {
	case .Version: write_line(VersionText)
	case .Fixture: write_fixture()
	case .Invalid: reject_command()
	}
}

write_fixture :: proc() {
	value := domain.Fixture{schema = domain.FixtureSchema, task = FixtureTask, run = FixtureRun, tick = FixtureTick}
	bytes := fixture.encode(value)
	write_bytes(bytes[:])
}

reject_command :: proc() {
	write_error(UsageText)
	exit_with_status(FailureStatus)
}

parse_command :: proc(arguments: []string) -> Command {
	if len(arguments) != RequiredArgumentCount { return .Invalid }
	switch arguments[1] {
	case VersionCommand: return .Version
	case FixtureCommand: return .Fixture
	}
	return .Invalid
}

read_arguments :: proc() -> []string {
	return os.args
}

write_line :: proc(text: string) {
	fmt.println(text)
}

write_bytes :: proc(bytes: []u8) {
	fmt.printf(BytePresentation, bytes)
}

write_error :: proc(text: string) {
	fmt.eprintln(text)
}

exit_with_status :: proc(status: int) {
	os.exit(status)
}
