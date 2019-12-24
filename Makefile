.PHONY : default build test clean

pub := /usr/local/bin/pub
dart := /usr/local/bin/dart

default: install-deps

install-deps:
	${pub} get

test:
	$(pub) run test --coverage=coverage
