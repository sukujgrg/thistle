BUILD_CONFIGURATION ?= debug
SWIFT = /usr/bin/swift
SWIFT_STRIP := $(if $(filter release,$(BUILD_CONFIGURATION)),-Xlinker -s)
BUILD_BIN_DIR = $(shell $(SWIFT) build -c $(BUILD_CONFIGURATION) --show-bin-path)
APP = bin/Thistle.app
AGENT_LABEL = dev.thistle.engine
APP_ICON = icon/Thistle.icon
APP_ICON_NAME = Thistle
APP_ICON_PARTIAL_INFO = .build/ThistleIconInfo.plist

# Release sequence:
#   git push && git tag -a vX.Y.Z -m "Thistle X.Y.Z" && git push origin vX.Y.Z
#   make release-github TAG=vX.Y.Z

NOTARY_PROFILE ?= thistleNotary
GH_REPO ?= sukujgrg/thistle
TAG ?=
NOTES_FILE ?=
BUILD_NUMBER ?=
TEAM_ID ?=
SIGNING_IDENTITY ?=
SKIP_VERSION_FILE_CHECK ?=

.PHONY: all build clean run fmt release-local release-notarize release-github

all: build

build:
	$(SWIFT) build -c $(BUILD_CONFIGURATION) $(SWIFT_STRIP)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	mkdir -p "$(APP)/Contents/Library/LaunchAgents"
	mkdir -p "$(APP)/Contents/Resources"
	cp Info.plist "$(APP)/Contents/Info.plist"
	if [ -f VERSION ]; then \
	  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $$(tr -d '[:space:]' < VERSION)" "$(APP)/Contents/Info.plist"; \
	fi
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
	codesign --force --sign - --entitlements ThistleEngine.entitlements "$(APP)/Contents/MacOS/ThistleEngine"
	codesign --force --sign - "$(APP)/Contents/MacOS/ThistleUpdater"
	codesign --force --sign - --entitlements ThistleMacOS.entitlements "$(APP)/Contents/MacOS/Thistle"
	codesign --force --sign - --entitlements ThistleMacOS.entitlements "$(APP)"

clean:
	$(SWIFT) package clean
	rm -rf bin build

run: build
	-killall ThistleEngine
	-killall Thistle
	-launchctl bootout gui/$$(id -u)/$(AGENT_LABEL)
	sleep 1
	open "$(APP)"

fmt:
	$(SWIFT) format --in-place --recursive Sources/

release-local:
	$(MAKE) BUILD_CONFIGURATION=release build

release-notarize:
	@if [ -z "$(NOTARY_PROFILE)" ]; then echo "Set NOTARY_PROFILE, e.g. make release-notarize NOTARY_PROFILE=thistleNotary"; exit 1; fi
	bash ./scripts/release-notarize-distribute.sh --notary-profile "$(NOTARY_PROFILE)" $(if $(TAG),--tag "$(TAG)") $(if $(BUILD_NUMBER),--build-number "$(BUILD_NUMBER)") $(if $(TEAM_ID),--team-id "$(TEAM_ID)") $(if $(SIGNING_IDENTITY),--signing-identity "$(SIGNING_IDENTITY)") $(if $(SKIP_VERSION_FILE_CHECK),--skip-version-file-check)

release-github:
	@if [ -z "$(NOTARY_PROFILE)" ]; then echo "Set NOTARY_PROFILE, e.g. make release-github NOTARY_PROFILE=thistleNotary GH_REPO=owner/repo"; exit 1; fi
	bash ./scripts/release-notarize-distribute.sh --notary-profile "$(NOTARY_PROFILE)" --github $(if $(GH_REPO),--repo "$(GH_REPO)") $(if $(TAG),--tag "$(TAG)") $(if $(BUILD_NUMBER),--build-number "$(BUILD_NUMBER)") $(if $(TEAM_ID),--team-id "$(TEAM_ID)") $(if $(SIGNING_IDENTITY),--signing-identity "$(SIGNING_IDENTITY)") $(if $(NOTES_FILE),--notes "$(NOTES_FILE)") $(if $(SKIP_VERSION_FILE_CHECK),--skip-version-file-check)
