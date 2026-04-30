# mdv — Markdown Viewer
#
# Quick start:
#   make           # checks prerequisites, then debug-builds via SwiftPM into ./build/mdv.app
#   make run       # build + launch
#   make install   # copy to /Applications/, register, and symlink CLI to /usr/local/bin/mdv
#   make help      # full target list
#
# Build is driven by `swift build` + ./build.sh — no Xcode IDE required.

CONFIG       := debug
APP          := build/mdv.app
CLI_SRC      := bin/mdv
CLI_DST      := /usr/local/bin/mdv
ICON_SRC     := MDV.png
ICON_DST     := mdv/AppIcon.icns
LSREGISTER   := /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
MIN_MACOS    := 13
MIN_SWIFT    := 5.9

.PHONY: all deps build release run clean install install-cli uninstall register icon help

all: build

help:
	@echo "Targets:"
	@echo "  make / build  Build $(CONFIG) into ./$(APP)  (default)"
	@echo "  release       Build release into ./$(APP)"
	@echo "  run           Build and launch mdv"
	@echo "  clean         Remove ./build/ and ./.build/"
	@echo "  install       Copy mdv.app to /Applications/, register it, symlink CLI"
	@echo "  install-cli   Symlink $(CLI_SRC) → $(CLI_DST) (sudo)"
	@echo "  uninstall     Remove /Applications/mdv.app and $(CLI_DST)"
	@echo "  register      Refresh LaunchServices for ./$(APP)"
	@echo "  icon          Regenerate $(ICON_DST) from $(ICON_SRC)"
	@echo "  deps          Verify build prerequisites (run automatically before build)"
	@echo "  help          Show this message"

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

deps:
	@echo "→ Checking build prerequisites..."
	@OS_VERSION=$$(sw_vers -productVersion 2>/dev/null); \
	if [ -z "$$OS_VERSION" ]; then \
	  echo "  ✗ Could not detect macOS version. mdv only builds on macOS."; exit 1; \
	fi; \
	OS_MAJOR=$$(echo $$OS_VERSION | cut -d. -f1); \
	if [ $$OS_MAJOR -lt $(MIN_MACOS) ]; then \
	  echo "  ✗ macOS $$OS_VERSION — mdv requires macOS $(MIN_MACOS).0 or newer."; exit 1; \
	fi; \
	echo "  ✓ macOS $$OS_VERSION"
	@command -v swift >/dev/null 2>&1 || { \
	  echo "  ✗ swift not on PATH. Install Xcode (App Store) or the Swift toolchain"; \
	  echo "    from https://swift.org/install/macos/, then re-run."; exit 1; }
	@SW_LINE=$$(swift --version 2>&1 | head -1); \
	echo "  ✓ $$SW_LINE"
	@if [ ! -f Package.swift ]; then \
	  echo "  ✗ Package.swift not found in $$(pwd). Run make from the repo root."; \
	  exit 1; \
	fi; \
	echo "  ✓ Package.swift present"
	@if [ ! -x ./build.sh ]; then \
	  echo "  ✗ ./build.sh missing or not executable."; exit 1; \
	fi; \
	echo "  ✓ build.sh present"
	@if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then \
	  echo "  ✓ sips + iconutil (for 'make icon')"; \
	else \
	  echo "  ⚠ sips or iconutil missing — 'make icon' won't run."; \
	fi
	@echo "→ Prerequisites OK."

# ---------------------------------------------------------------------------
# Build (delegates to ./build.sh, which runs `swift build` + bundles the .app)
# ---------------------------------------------------------------------------

build: deps
	./build.sh $(CONFIG)

release: deps
	./build.sh release

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
	@$(MAKE) --no-print-directory install-cli
	@echo "  → To set as default for .md files: right-click any .md → Get Info → Open with → mdv → Change All."

install-cli:
	@if [ ! -x "$(CLI_SRC)" ]; then echo "✗ $(CLI_SRC) missing or not executable"; exit 1; fi
	@SRC_ABS="$$(cd "$$(dirname $(CLI_SRC))" && pwd)/$$(basename $(CLI_SRC))"; \
	$(MAKE) --no-print-directory _sudo CMD="mkdir -p '$$(dirname $(CLI_DST))'" \
	   ASKPASS_PROMPT="Create $$(dirname $(CLI_DST))" >/dev/null; \
	$(MAKE) --no-print-directory _sudo CMD="ln -sf '$$SRC_ABS' '$(CLI_DST)'" \
	   ASKPASS_PROMPT="Symlink mdv CLI into $(CLI_DST)" \
	&& echo "✓ linked $(CLI_DST) → $$SRC_ABS" \
	|| { echo "✗ failed to symlink $(CLI_DST). Run manually:"; \
	     echo "    sudo ln -sf $$SRC_ABS $(CLI_DST)"; exit 1; }

# ---------------------------------------------------------------------------
# Internal helper: run $(CMD) with sudo, falling back to a GUI password
# prompt (osascript) when there's no terminal. Lets `make install` work from
# editors / Claude Code / IDE shells that lack a TTY.
#
# Args:
#   CMD             — shell command to run (required)
#   ASKPASS_PROMPT  — text shown in the GUI dialog (optional)
# ---------------------------------------------------------------------------
_sudo:
	@if [ -z "$(CMD)" ]; then echo "✗ _sudo: CMD is required"; exit 1; fi
	@if eval "$(CMD)" 2>/dev/null; then exit 0; fi; \
	PROMPT="$${ASKPASS_PROMPT:-Run a privileged command for mdv}"; \
	if [ -t 0 ]; then \
	  sudo sh -c "$(CMD)"; \
	else \
	  ASKPASS=$$(mktemp -t mdv-askpass.XXXXXX); \
	  trap 'rm -f "$$ASKPASS"' EXIT; \
	  printf '#!/bin/sh\nosascript -e '\''display dialog "%s" with hidden answer default answer "" with title "mdv install"'\'' -e '\''text returned of result'\'' 2>/dev/null\n' "$$PROMPT" > "$$ASKPASS"; \
	  chmod +x "$$ASKPASS"; \
	  SUDO_ASKPASS="$$ASKPASS" sudo -A sh -c "$(CMD)"; \
	fi

uninstall:
	@if [ -L "$(CLI_DST)" ] || [ -e "$(CLI_DST)" ]; then \
	  rm -f "$(CLI_DST)" 2>/dev/null || sudo rm -f "$(CLI_DST)"; \
	  echo "✓ removed $(CLI_DST)"; \
	else \
	  echo "  (no $(CLI_DST) to remove)"; \
	fi
	@if [ -d /Applications/mdv.app ]; then \
	  rm -rf /Applications/mdv.app 2>/dev/null || sudo rm -rf /Applications/mdv.app; \
	  echo "✓ removed /Applications/mdv.app"; \
	else \
	  echo "  (no /Applications/mdv.app to remove)"; \
	fi

register: build
	$(LSREGISTER) -f "$(APP)"
	@echo "✓ registered $(APP) with LaunchServices"

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

clean:
	rm -rf build .build build_icon
	@echo "✓ removed build/, .build/, and build_icon/"

# ---------------------------------------------------------------------------
# Icon (regenerate from MDV.png)
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
