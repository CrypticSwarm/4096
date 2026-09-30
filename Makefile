# Developer entry points. CI runs these same targets.
#
# Core targets (build, test, lint, format) need only a Swift 6 toolchain and
# work on Linux and macOS. ios-* targets need macOS with Xcode and XcodeGen.
#
# macOS ships GNU make 3.81, which ignores .SHELLFLAGS, so recipes that pipe
# set pipefail themselves.

SHELL := /bin/bash
.DEFAULT_GOAL := help

PACKAGE := GameCore

# Every Swift file in the repo, skipping hidden dirs (.build, .git, .swiftpm)
# and build output.
SWIFT_FILES = $(shell find . -mindepth 1 \( -name '.*' -o -name build -o -name DerivedData \) -prune \
	-o -name '*.swift' -print)

PROJECT := Game4096.xcodeproj
SCHEME := Game4096
# The device must exist in the selected Xcode's simulator runtimes; CI's Xcode
# is XCODE_VERSION in .github/workflows/ios.yml.
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17,OS=latest
BUILD_DIR := build
RESULT_BUNDLE := $(BUILD_DIR)/TestResults.xcresult
XCODEBUILD_LOG := $(BUILD_DIR)/xcodebuild.log
ATTACHMENTS_DIR := $(BUILD_DIR)/attachments
# Pretty-printer for xcodebuild output; CI adds --renderer github-actions.
XCBEAUTIFY ?= $(if $(shell command -v xcbeautify),xcbeautify,cat)

.PHONY: help build test lint format check ios-project ios-test ios-attachments ios-summary clean

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

build: ## Build the GameCore package
	swift build --package-path $(PACKAGE)

test: ## Run the GameCore tests
	swift test --package-path $(PACKAGE)

lint: ## Check formatting of all Swift sources (strict)
	swift format lint --strict --parallel $(SWIFT_FILES)

format: ## Reformat all Swift sources in place
	swift format format --in-place --parallel $(SWIFT_FILES)

# The Core CI job runs these as separate steps (so lint reports even when tests
# fail); keep the two in sync.
check: build test lint ## Build, test and lint the core

ios-project: ## Generate the Xcode project from project.yml
	xcodegen generate

ios-test: ios-project ## Build and run app, UI and GameCore tests on the simulator (macOS)
	rm -rf $(RESULT_BUNDLE)
	mkdir -p $(BUILD_DIR)
	set -o pipefail; xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(IOS_DESTINATION)' \
		-resultBundlePath $(RESULT_BUNDLE) \
		2>&1 | tee $(XCODEBUILD_LOG) | $(XCBEAUTIFY)

ios-attachments: ## Export screenshots from the last ios-test run to build/attachments (macOS)
	scripts/export-attachments.sh $(RESULT_BUNDLE) $(ATTACHMENTS_DIR)

ios-summary: ## Print a Markdown summary of the last ios-test run (macOS)
	@scripts/ci/xcresult-summary.sh $(RESULT_BUNDLE) $(XCODEBUILD_LOG) $(ATTACHMENTS_DIR)

clean: ## Remove build outputs and the generated project
	rm -rf $(PACKAGE)/.build $(BUILD_DIR) $(PROJECT)
