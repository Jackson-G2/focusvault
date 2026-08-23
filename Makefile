.PHONY: test build integration

test:
	swift run focusvault-self-test

build:
	swift build -c release

integration:
	./scripts/integration-test.sh
