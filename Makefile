# mdv — Markdown Viewer
#
# Quick start:
#   make           # checks prerequisites, then debug-builds into ./build/
#   make run       # build + launch
#   make install   # copy to /Applications/ and register with LaunchServices
#   make help      # full target list
#
# `make` always runs the prerequisite checks first, so a fresh clone gets
# actionable errors (missing Xcode, license unaccepted, etc.) instead of a
# wall of xcodebuild output.

PROJECT      := mdv.xcodeproj
SCHEME       := mdv
CONFIG       := Debug
DERIVED      := build
BUILT_DIR    := $(DERIVED)/Build/Products/$(CONFIG)
APP          := $(BUILT_DIR)/mdv.app
ICON_SRC     := MDV.png
ICON_DST     := mdv/AppIcon.icns
LSREGISTER   := /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
MIN_MACOS    := 13
MIN_XCODE    := 14

.PHONY: all deps build release run clean install register icon help

all: build

help:
	@echo "Targets:"
	@echo "  make / build  Build $(CONFIG) into ./$(DERIVED)/  (default)"
	@echo "  release       Build Release into ./$(DERIVED)/"
	@echo "  run           Build and launch mdv"
	@echo "  clean         Remove ./$(DERIVED)/ and ./build_icon/"
	@echo "  install       Copy mdv.app to /Applications/ + refresh LaunchServices"
	@echo "  register      Refresh LaunchServices for ./$(BUILT_DIR)/mdv.app"
	@echo "  icon          Regenerate $(ICON_DST) from $(ICON_SRC)"
	@echo "  deps          Verify build prerequisites (run automatically before build)"
	@echo "  help          Show this message"

# ---------------------------------------------------------------------------
# Prerequisite checks
# Designed to give the next-most-useful error message at every step, so a
# fresh clone produces actionable guidance instead of cryptic xcodebuild output.
# ---------------------------------------------------------------------------

deps:
	@echo "→ Checking build prerequisites..."
	@# --- macOS version ---
	@OS_VERSION=$$(sw_vers -productVersion 2>/dev/null); \
	if [ -z "$$OS_VERSION" ]; then \
	  echo "  ✗ Could not detect macOS version (sw_vers failed). mdv only builds on macOS."; exit 1; \
	fi; \
	OS_MAJOR=$$(echo $$OS_VERSION | cut -d. -f1); \
	if [ $$OS_MAJOR -lt $(MIN_MACOS) ]; then \
	  echo "  ✗ macOS $$OS_VERSION — mdv requires macOS $(MIN_MACOS).0 or newer."; exit 1; \
	fi; \
	echo "  ✓ macOS $$OS_VERSION"
	@# --- xcode-select active developer dir ---
	@XCODE_PATH=$$(xcode-select -p 2>/dev/null); \
	if [ -z "$$XCODE_PATH" ]; then \
	  echo "  ✗ No active Xcode developer directory set."; \
	  echo "    Install Xcode from the App Store, then run:"; \
	  echo "        sudo xcode-select -s /Applications/Xcode.app"; \
	  exit 1; \
	fi; \
	case "$$XCODE_PATH" in \
	  *CommandLineTools*) \
	    echo "  ✗ xcode-select points to Command Line Tools, not a full Xcode install:"; \
	    echo "        $$XCODE_PATH"; \
	    echo "    Command Line Tools cannot build .app bundles. Install Xcode from the"; \
	    echo "    App Store, then run:"; \
	    echo "        sudo xcode-select -s /Applications/Xcode.app"; \
	    exit 1;; \
	esac; \
	echo "  ✓ developer dir: $$XCODE_PATH"
	@# --- xcodebuild on PATH and operational ---
	@command -v xcodebuild >/dev/null 2>&1 || { \
	  echo "  ✗ xcodebuild not on PATH. Install Xcode from the App Store."; exit 1; }
	@XB_OUT=$$(xcodebuild -version 2>&1); XB_RC=$$?; \
	if [ $$XB_RC -ne 0 ]; then \
	  if echo "$$XB_OUT" | grep -qi license; then \
	    echo "  ✗ The Xcode license has not been accepted. Run:"; \
	    echo "        sudo xcodebuild -license accept"; \
	  elif echo "$$XB_OUT" | grep -qi "first launch"; then \
	    echo "  ✗ Xcode needs first-launch setup. Run:"; \
	    echo "        sudo xcodebuild -runFirstLaunch"; \
	  else \
	    echo "  ✗ xcodebuild is not operational:"; \
	    echo "$$XB_OUT" | sed 's/^/      /'; \
	  fi; \
	  exit 1; \
	fi; \
	XB_LINE=$$(echo "$$XB_OUT" | head -1); \
	XB_MAJOR=$$(echo $$XB_LINE | sed -E 's/Xcode ([0-9]+).*/\1/'); \
	if [ -n "$$XB_MAJOR" ] && [ $$XB_MAJOR -lt $(MIN_XCODE) ] 2>/dev/null; then \
	  echo "  ✗ $$XB_LINE — mdv's project format needs Xcode $(MIN_XCODE).0 or newer."; \
	  echo "    Update Xcode from the App Store."; exit 1; \
	fi; \
	echo "  ✓ $$XB_LINE"
	@# --- macOS SDK available ---
	@if ! xcodebuild -showsdks 2>/dev/null | grep -qi macosx; then \
	  echo "  ✗ No macOS SDK is registered with this Xcode install."; \
	  echo "    Open Xcode once, agree to the terms, and let it install components."; \
	  exit 1; \
	fi; \
	SDK=$$(xcodebuild -showsdks 2>/dev/null | grep -i macosx | tail -1 | awk '{print $$NF}'); \
	echo "  ✓ macOS SDK: $$SDK"
	@# --- project file present (catches "make from wrong directory") ---
	@if [ ! -d "$(PROJECT)" ]; then \
	  echo "  ✗ $(PROJECT) not found in $$(pwd)."; \
	  echo "    Run make from the repo root."; exit 1; \
	fi; \
	echo "  ✓ project: $(PROJECT)"
	@# --- icon helpers (optional; only required for `make icon`) ---
	@if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then \
	  echo "  ✓ sips + iconutil (for 'make icon')"; \
	else \
	  echo "  ⚠ sips or iconutil missing — 'make icon' won't run, but 'make build' is fine."; \
	fi
	@echo "→ Prerequisites OK."

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build: deps
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration $(CONFIG) \
	  -derivedDataPath $(DERIVED) \
	  build

release: deps
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration Release \
	  -derivedDataPath $(DERIVED) \
	  build

# ---------------------------------------------------------------------------
# Run / install / register
# ---------------------------------------------------------------------------

run: build
	open "$(APP)"

install: build
	@if [ ! -d "$(APP)" ]; then echo "✗ $(APP) missing — build failed?"; exit 1; fi
	rm -rf /Applications/mdv.app
	cp -R "$(APP)" /Applications/
	@echo "✓ copied to /Applications/mdv.app"
	$(LSREGISTER) -f /Applications/mdv.app
	@echo "✓ registered /Applications/mdv.app with LaunchServices"
	@echo "  → To set as default for .md files: right-click any .md → Get Info → Open with → mdv → Change All."

register: build
	$(LSREGISTER) -f "$(APP)"
	@echo "✓ registered $(APP) with LaunchServices"

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

clean:
	rm -rf $(DERIVED) build_icon
	@echo "✓ removed $(DERIVED)/ and build_icon/"

# ---------------------------------------------------------------------------
# Icon (regenerate from MDV.png)
# Only needed if MDV.png changes; the compiled .icns is committed.
# ---------------------------------------------------------------------------

icon: $(ICON_DST)

$(ICON_DST): $(ICON_SRC)
	@command -v sips     >/dev/null 2>&1 || { echo "✗ sips not found";     exit 1; }
	@command -v iconutil >/dev/null 2>&1 || { echo "✗ iconutil not found"; exit 1; }
	@rm -rf build_icon
	@mkdir -p build_icon/AppIcon.iconset
	@sips -p 1024 1024 --padColor FFFFFF "$(ICON_SRC)" --out build_icon/square.png >/dev/null
	@SQ=build_icon/square.png; SET=build_icon/AppIcon.iconset; \
	 sips -z 16   16   $$SQ --out $$SET/icon_16x16.png      >/dev/null && \
	 sips -z 32   32   $$SQ --out $$SET/icon_16x16@2x.png   >/dev/null && \
	 sips -z 32   32   $$SQ --out $$SET/icon_32x32.png      >/dev/null && \
	 sips -z 64   64   $$SQ --out $$SET/icon_32x32@2x.png   >/dev/null && \
	 sips -z 128  128  $$SQ --out $$SET/icon_128x128.png    >/dev/null && \
	 sips -z 256  256  $$SQ --out $$SET/icon_128x128@2x.png >/dev/null && \
	 sips -z 256  256  $$SQ --out $$SET/icon_256x256.png    >/dev/null && \
	 sips -z 512  512  $$SQ --out $$SET/icon_256x256@2x.png >/dev/null && \
	 sips -z 512  512  $$SQ --out $$SET/icon_512x512.png    >/dev/null && \
	 sips -z 1024 1024 $$SQ --out $$SET/icon_512x512@2x.png >/dev/null
	@iconutil -c icns build_icon/AppIcon.iconset -o "$(ICON_DST)"
	@echo "✓ regenerated $(ICON_DST) from $(ICON_SRC)"
