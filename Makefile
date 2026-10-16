.DEFAULT_GOAL := help

BUILD_CONFIGURATION ?= debug
SWIFT = /usr/bin/swift
SWIFT_BUILD_PATH ?= .build
SWIFT_BUILD_FLAGS = --scratch-path "$(SWIFT_BUILD_PATH)" --arch arm64
SWIFT_STRIP := $(if $(filter release,$(BUILD_CONFIGURATION)),-Xlinker -s)
BUILD_BIN_DIR = $(shell $(SWIFT) build $(SWIFT_BUILD_FLAGS) -c $(BUILD_CONFIGURATION) --show-bin-path)
APP = bin/Thistle.app
AGENT_LABEL = dev.thistle.engine
APP_ICON = icon/Thistle.icon
APP_ICON_NAME = Thistle
APP_ICON_PARTIAL_INFO = $(SWIFT_BUILD_PATH)/ThistleIconInfo.plist
APP_INSTALL_DIR ?= $(HOME)/Applications

NOTARY_PROFILE ?= thistleNotary
NOTES_FILE ?=
SIGNING_IDENTITY ?=
# Optional notes must be outside the checkout, e.g. /tmp/thistle-notes.md.

.PHONY: help all build app clean run fmt test test-release release release-check release-notarize release-publish

help:
	@printf '%s\n' \
	  'make build             Build an Apple Silicon app into ~/Applications' \
	  'make run               Build and open a debug app from bin/' \
	  'make release           Validate, sign, notarize, tag, and publish from this Mac' \
	  'make release-check     Check source, destination, and CI only' \
	  'make release-notarize  Produce signed local artifacts without publishing' \
	  'make release-publish   Publish saved artifacts without building or notarizing' \
	  'make test              Run app and release regression tests' \
	  'make clean             Remove build caches; preserve saved releases'

all: build

build:
	APP_INSTALL_DIR="$(APP_INSTALL_DIR)" SIGNING_IDENTITY="$(SIGNING_IDENTITY)" bash scripts/build.sh

# Bundle assembly shared by local development and the distribution driver.
app:
	$(SWIFT) build $(SWIFT_BUILD_FLAGS) -c $(BUILD_CONFIGURATION) $(SWIFT_STRIP)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	mkdir -p "$(APP)/Contents/Library/LaunchAgents"
	mkdir -p "$(APP)/Contents/Resources"
	bash scripts/generate-info-plist.sh VERSION Info.plist "$(APP)/Contents/Info.plist"
	cp LaunchAgents/$(AGENT_LABEL).plist "$(APP)/Contents/Library/LaunchAgents/$(AGENT_LABEL).plist"
	install "$(BUILD_BIN_DIR)/Thistle" "$(APP)/Contents/MacOS/Thistle"
	install "$(BUILD_BIN_DIR)/ThistleEngine" "$(APP)/Contents/MacOS/ThistleEngine"
	install "$(BUILD_BIN_DIR)/ThistleUpdater" "$(APP)/Contents/MacOS/ThistleUpdater"
	xcrun actool \
		--compile "$(APP)/Contents/Resources" \
		--platform macosx \
		--target-device mac \
		--minimum-deployment-target 26.0 \
		--app-icon "$(APP_ICON_NAME)" \
		--output-partial-info-plist "$(APP_ICON_PARTIAL_INFO)" \
		--standalone-icon-behavior all \
		--output-format human-readable-text \
		--warnings --notices --errors \
		"$(APP_ICON)"
	bash scripts/sign-local-app.sh "$(APP)" "$(SIGNING_IDENTITY)"

clean:
	python3 scripts/release.py --clean

run: app
	-killall ThistleEngine
	-killall Thistle
	-launchctl bootout gui/$$(id -u)/$(AGENT_LABEL)
	sleep 1
	open "$(APP)"

fmt:
	$(SWIFT) format --in-place --recursive Sources/

test-release:
	python3 scripts/test-release-workflow.py

test: test-release
	$(SWIFT) test --arch arm64

ifneq ($(filter release release-check release-notarize release-publish,$(MAKECMDGOALS)),)
ifneq ($(strip $(VERSION)$(TAG)$(BUILD_NUMBER)$(SKIP_VERSION_FILE_CHECK)$(GH_REPO)$(TEAM_ID)$(SIGNING_IDENTITY)),)
$(error Release settings are derived automatically. Edit VERSION, commit and merge or push to main, then run make release without VERSION, TAG, BUILD_NUMBER, SKIP_VERSION_FILE_CHECK, GH_REPO, TEAM_ID or SIGNING_IDENTITY overrides)
endif
endif

release:
	python3 scripts/release.py --notary-profile "$(NOTARY_PROFILE)" $(if $(NOTES_FILE),--notes "$(NOTES_FILE)")

release-check:
	python3 scripts/release.py --check

release-notarize:
	python3 scripts/release.py --notary-profile "$(NOTARY_PROFILE)" --no-publish

release-publish:
	python3 scripts/release.py --publish-only $(if $(NOTES_FILE),--notes "$(NOTES_FILE)")
