package request_window_test

import "core:testing"
import a "../../../src/audit"
import store "../../../src/store"

@(test)
commit_window_is_exclusive :: proc(t: ^testing.T) {
	issue := a.RequestIssued{start_ms=900, deadline_ms=30_900}
	testing.expect(t,!store.in_request_window(issue,-1))
	testing.expect(t,!store.in_request_window(issue,899))
	testing.expect(t,store.in_request_window(issue,900))
	testing.expect(t,store.in_request_window(issue,30_899))
	testing.expect(t,!store.in_request_window(issue,30_900))
	testing.expect(t,!store.in_request_window(issue,30_901))
}
