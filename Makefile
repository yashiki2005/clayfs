# clayfsctl と clayfs_tool は同じ場所に置く (clayfsctl が隣の clayfs_tool を呼ぶ)
BINDIR ?= $(HOME)/build/bin

install:
	mkdir -p $(BINDIR)
	install -m 755 clayfsctl clayfs_tool $(BINDIR)/

.PHONY: install
