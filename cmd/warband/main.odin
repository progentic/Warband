package main

import "core:fmt"
import "core:os"
import "../../src/domain"
import "../../src/fixture"

Command :: enum { Version, Fixture, Invalid }
OutputChannel :: enum { Stdout, Stderr }
OutputFormat :: enum { Text, Bytes }
Presentation :: struct {
	channel: OutputChannel,
	format:  OutputFormat,
	text:    string,
	bytes:   fixture.Encoded,
	status:  int,
}
VersionText :: "Warband Phase 1 foundation (no execution authority)"
UsageText :: "usage: warband version | fixture"
FailureStatus :: 2
SuccessStatus :: 0
RequiredArgumentCount :: 2
CommandArgumentIndex :: 1
EmptyArgument :: ""
VersionCommand :: "version"
FixtureCommand :: "fixture"
BytePresentation :: "%02x\n"
FixtureTask :: domain.TaskId(1)
FixtureRun :: domain.RunId(2)
FixtureTick :: domain.Tick(3)

main :: proc() {
	arguments := read_arguments()
	command := parse_command(arguments)
	result := describe_command(command)
	write_result(result)
	exit_with_status(result.status)
}

parse_command :: proc(arguments: []string) -> Command {
	token := read_fixed_argument(arguments, RequiredArgumentCount, CommandArgumentIndex)
	switch token {
	case VersionCommand: return .Version
	case FixtureCommand: return .Fixture
	}
	return .Invalid
}

describe_command :: proc(command: Command) -> Presentation {
	if command == .Version {
		return {channel = .Stdout, format = .Text, text = VersionText, status = SuccessStatus}
	}
	if command == .Fixture {
		value := domain.Fixture{schema = domain.FixtureSchema, task = FixtureTask, run = FixtureRun, tick = FixtureTick}
		return {channel = .Stdout, format = .Bytes, bytes = fixture.encode(value), status = SuccessStatus}
	}
	return {channel = .Stderr, format = .Text, text = UsageText, status = FailureStatus}
}

write_result :: proc(result: Presentation) {
	stream := output_stream(result.channel)
	if result.format == .Bytes {
		bytes := result.bytes
		write_bytes(stream, bytes[:])
		return
	}
	write_line(stream, result.text)
}

output_stream :: proc(channel: OutputChannel) -> ^os.File {
	if channel == .Stderr { return os.stderr }
	return os.stdout
}

read_arguments :: proc() -> []string {
	return os.args
}

read_fixed_argument :: proc(arguments: []string, expected_count, index: int) -> string {
	if len(arguments) != expected_count { return EmptyArgument }
	return arguments[index]
}

write_line :: proc(stream: ^os.File, text: string) {
	fmt.fprintln(stream, text)
}

write_bytes :: proc(stream: ^os.File, bytes: []u8) {
	fmt.fprintf(stream, BytePresentation, bytes)
}

exit_with_status :: proc(status: int) {
	os.exit(status)
}
