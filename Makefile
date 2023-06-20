.PHONY : default build test clean

dart := /usr/local/bin/dart

default: install-deps

install-deps:
	${dart} pub get

test:
	$(dart) test --coverage=coverage
