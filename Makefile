.PHONY: test compatibility-test supporter-monitor-test build integration extension-test short-form-test timed-session-test research-test app app-test

app:
	scripts/package-app.sh

app-test:
	scripts/app-smoke-test.sh

test:
	python3 -m unittest discover -s ResearchAgent/tests -v
	python3 -m unittest scripts.test_vaulty_supporter_monitor -v
	swift run vaulty-self-test
	node BrowserExtension/tests/policy.test.js
	node BrowserExtension/tests/short-form.test.js
	node BrowserExtension/tests/session-policy.test.js

compatibility-test:
	swift run focusvault-self-test

supporter-monitor-test:
	python3 -m unittest scripts.test_vaulty_supporter_monitor -v

research-test:
	python3 -m unittest discover -s ResearchAgent/tests -v

extension-test:
	node BrowserExtension/tests/policy.test.js
	node BrowserExtension/tests/short-form.test.js
	node BrowserExtension/tests/session-policy.test.js

short-form-test:
	node BrowserExtension/tests/short-form.test.js
	swift run vaulty-self-test

timed-session-test:
	node BrowserExtension/tests/session-policy.test.js
	swift run vaulty-self-test

build:
	swift build -c release

integration:
	./scripts/integration-test.sh
