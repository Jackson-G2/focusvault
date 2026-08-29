.PHONY: test build integration extension-test app

app:
	scripts/package-app.sh

test:
	swift run focusvault-self-test
	node BrowserExtension/tests/policy.test.js

extension-test:
	node BrowserExtension/tests/policy.test.js

build:
	swift build -c release

integration:
	./scripts/integration-test.sh
