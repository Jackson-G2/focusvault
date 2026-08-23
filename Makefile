.PHONY: test build integration

test:
	swift run frostwall-self-test

build:
	swift build -c release

integration:
	./scripts/integration-test.sh
