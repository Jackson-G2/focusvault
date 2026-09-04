.PHONY: test build integration extension-test research-test app

app:
	scripts/package-app.sh

test:
	python3 -m unittest discover -s ResearchAgent/tests -v
	swift run focusvault-self-test
	node BrowserExtension/tests/policy.test.js

research-test:
	python3 -m unittest discover -s ResearchAgent/tests -v

extension-test:
	node BrowserExtension/tests/policy.test.js

build:
	swift build -c release

integration:
	./scripts/integration-test.sh
