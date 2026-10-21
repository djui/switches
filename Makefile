.PHONY: help convert-sounds icons generate test build install release clean

help:
	@echo "make convert-sounds  Convert Sounds/ into Switches/Resources/Themes/"
	@echo "make icons           Render app and menu bar icons"
	@echo "make generate        Generate Switches.xcodeproj (XcodeGen)"
	@echo "make test            Run SwitchesCore unit tests"
	@echo "make build           Release build -> build/Switches.app"
	@echo "make install         Build, install to /Applications and restart"
	@echo "make release [PART=patch|minor|major] [NOTES='...']"

convert-sounds:
	swift scripts/convert_sounds.swift

icons:
	swift scripts/make_icons.swift

generate:
	xcodegen generate

test:
	swift test --package-path Packages/SwitchesCore

build:
	scripts/build_release.sh

install:
	scripts/install_local.sh

PART ?= patch
NOTES ?=
release:
	scripts/release.sh $(PART) "$(NOTES)"

clean:
	rm -rf build dist Switches.xcodeproj Packages/SwitchesCore/.build
