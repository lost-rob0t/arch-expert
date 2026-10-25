.PHONY: test shell install

PREFIX ?= /usr/local
DESTDIR ?=

test:
	swipl -q -g '(run_tests -> halt(0) ; halt(1))' tests/test_arch_expert.pl

shell:
	./bin/arch-expert shell

install:
	install -Dm755 bin/arch-expert $(DESTDIR)$(PREFIX)/bin/arch-expert
	install -d $(DESTDIR)$(PREFIX)/share/arch-expert
	cp -r prolog kb $(DESTDIR)$(PREFIX)/share/arch-expert/
