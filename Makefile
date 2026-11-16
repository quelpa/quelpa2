EMACS ?= emacs
export RUN_NETWORK_TESTS ?= 1

.PHONY: all test local clean

all: test

test:
	$(EMACS) -Q -batch -L . -l test/quelpa2-test.el -f ert-run-tests-batch-and-exit

local:
	RUN_NETWORK_TESTS=0 $(MAKE) test

# Clean up any compiled byte-code files
clean:
	rm -f *.elc test/*.elc
