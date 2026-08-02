APP_HOME := $(HOME)/Applications/Cull.app

.PHONY: build test bundle install run

build:
	swift build

test:
	swift test

bundle:
	Support/bundle.sh release

install: bundle
	pkill -x Cull || true
	mkdir -p $(HOME)/Applications
	rm -rf $(APP_HOME)
	ditto dist/Cull.app $(APP_HOME)

run: install
	open $(APP_HOME)
