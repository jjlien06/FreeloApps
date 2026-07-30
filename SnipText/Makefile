APP_HOME := $(HOME)/Applications/SnipText.app

.PHONY: build test bundle install run logs

build:
	swift build

test:
	swift test

bundle:
	Support/bundle.sh release

install: bundle
	pkill -x SnipText || true
	mkdir -p $(HOME)/Applications
	rm -rf $(APP_HOME)
	ditto dist/SnipText.app $(APP_HOME)

run: install
	open $(APP_HOME)

logs:
	log stream --predicate 'subsystem == "com.jeremylien.SnipText"' --level debug
