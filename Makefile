EMACS ?= emacs
export RUN_NETWORK_TESTS ?= 1

.PHONY: all test clean

all: test

# Run standard offline unit and sandbox tests
test:
	$(EMACS) -Q -batch -L . -l test/quelpa2-test.el -f ert-run-tests-batch-and-exit

# Clean up any compiled byte-code files
clean:
	rm -f *.elc test/*.elc
