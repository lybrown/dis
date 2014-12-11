testl:
	make l=-l test
	make test

test:
	./dis.pl -x $(l) ransack.xex > r.asm
	xasm r.asm
	cmp ransack.xex r.obx
	./dis.pl -p $(l) daah_those_acid_pills.prg > daah.asm
	xasm daah.asm
	cmp daah_those_acid_pills.prg daah.obx
	./dis.pl -e 1000 -e 9006 -v FFFE -d 9101 $(l) game.mem > g.asm
	xasm g.asm
	cmp game.mem g.obx
	@echo "PASS"
