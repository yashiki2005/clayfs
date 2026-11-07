BINDIR ?= $(HOME)/build/bin
APPDIR ?= $(HOME)/Applications

all: build

build:
	swift build -c release

test:
	swift test

app: build
	mkdir -p build/ClayFS.app/Contents/MacOS
	mkdir -p build/ClayFS.app/Contents/Resources
	cp Sources/ClayFSApp/Info.plist build/ClayFS.app/Contents/Info.plist
	echo "APPL????" > build/ClayFS.app/Contents/PkgInfo
	cp $$(swift build -c release --show-bin-path)/ClayFSApp build/ClayFS.app/Contents/MacOS/ClayFSApp

install: app
	mkdir -p $(BINDIR)
	install -m 755 $$(swift build -c release --show-bin-path)/clayfs $(BINDIR)/clayfs
	mkdir -p $(APPDIR)
	rm -rf $(APPDIR)/ClayFS.app
	cp -R build/ClayFS.app $(APPDIR)/ClayFS.app
	@echo "Installed clayfs CLI to $(BINDIR)/clayfs"
	@echo "Installed ClayFS.app to $(APPDIR)/ClayFS.app"

install-legacy:
	mkdir -p $(BINDIR)
	install -m 755 clayfsctl clayfs_tool $(BINDIR)/

clean:
	rm -rf .build build

.PHONY: all build test app install install-legacy clean
