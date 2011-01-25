.PHONY: all install

# This is a fake Makefile, and only works on Linux.
# It also requires rsync. It's really bad. Replace me!

MYLIB=~/.greynoise/lib/perl5/
MYBIN=~/.bin/

all:
	cat Makefile

install:
	mkdir -p $(MYLIB)
	rsync -av ./lib/ $(MYLIB)
	mkdir -p $(MYBIN)
	rsync -av ./bin/ $(MYBIN)
