.PHONY : default build test clean

default: install-deps

install-deps:
	dart pub get

test:
ifndef files
	dart test
else
	dart test ${files}
endif	

cov:
ifndef files
	flutter test --coverage
else
	flutter test ${files} --coverage
endif
	rm -rf coverage/html
	genhtml coverage/lcov.info -o coverage/html
	open coverage/html/src/lib/src/index.html

publish:
	dart pub publish

clean:
	rm -f pubspec.lock .packages