SHELL=/bin/bash

all:
	time make test
	time make test l=-l

test:
	./dis -x $(l) -a hardware.dop ransack.xex > r.asm
	xasm r.asm
	cmp ransack.xex r.obx
	./dis -p $(l) daah_those_acid_pills.prg -c st100=416A > daah.asm
	xasm daah.asm
	cmp daah_those_acid_pills.prg daah.obx
	./dis -c 1000 -c 9006 -v FFFE -d 9101 $(l) game.mem > g.asm
	xasm g.asm
	cmp game.mem g.obx
	./dis -l -a hardware.dop -a sys.dop selftest.mem > s.asm
	xasm s.asm
	cmp selftest.mem s.obx
	./dis -l -t sap -a hardware.dop A_type.sap > a.asm
	xasm a.asm
	cmp A_Type.sap a.obx
	@echo "PASS"

.PHONY: testl test
