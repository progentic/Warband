package main

import "core:fmt"
import "core:os"
import "core:strings"
import "../../src/store"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("usage: provision-store <database-path>")
		os.exit(2)
	}
	path := strings.clone_to_cstring(os.args[1])
	result := store.provision_store(path)
	delete(path)
	if result != .None {
		fmt.eprintln("provision-store:", result)
		os.exit(1)
	}
}
