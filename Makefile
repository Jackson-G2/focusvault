.PHONY: test verify benchmark source-check compatibility-test supporter-monitor-test build integration extension-test short-form-test timed-session-test research-test app app-test

app:
	scripts/package-app.sh

app-test:
	scripts/app-smoke-test.sh

test:
	python3 -m unittest discover -s ResearchAgent/tests -v
	python3 -m unittest discover -s scripts -p 'test_*.py' -v
	swift run vaulty-self-test
	$(MAKE) extension-test

compatibility-test:
	swift run focusvault-self-test

supporter-monitor-test:
	python3 -m unittest scripts.test_vaulty_supporter_monitor -v

research-test:
	python3 -m unittest discover -s ResearchAgent/tests -v

extension-test:
	@set -e; for suite in BrowserExtension/tests/*.test.js; do node "$$suite"; done

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

# Deliberately sequential: app packaging and integration share SwiftPM outputs.
verify:
	$(MAKE) test
	$(MAKE) compatibility-test
	$(MAKE) integration
	$(MAKE) app-test
	$(MAKE) source-check

source-check:
	python3 scripts/check-app-contracts.py
	python3 scripts/check-source-syntax.py
	@for script in scripts/*.sh; do bash -n "$$script" || exit $$?; done
	git diff --check

benchmark:
	swift build --product vaulty-app
	python3 scripts/benchmark-status.py
