SHELL=/bin/bash

testl:
	time make test
	time make l=-l test

test:
	./dis.pl -x $(l) ransack.xex > r.asm
	xasm r.asm
	cmp ransack.xex r.obx
	./dis.pl -p $(l) daah_those_acid_pills.prg > daah.asm
	xasm daah.asm
	cmp daah_those_acid_pills.prg daah.obx
	./dis.pl -c 1000 -c 9006 -v FFFE -d 9101 $(l) game.mem > g.asm
	xasm g.asm
	cmp game.mem g.obx
	@echo "PASS"

.PHONY: testl test
