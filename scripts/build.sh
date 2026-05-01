#!/bin/bash

# Usage4Claude build script
# Compiles the Xcode project, exports the .app, packages a DMG, notarizes it,
# and signs it for Sparkle distribution.
# Usage: ./scripts/build.sh [--no-clean] [--config Release|Debug] [--verbose|-v]

set -e  # Exit on any error
set -o pipefail  # Fail the whole pipeline if any stage fails

# ============================================
# Color output
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# Helper functions
# ============================================
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ Error: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  Warning: $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# ============================================
# Configuration
# ============================================
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="Usage4Claude"
PRODUCT_NAME="U4Claude"
SCHEME_NAME="Usage4Claude"
XCODEPROJ="${PROJECT_ROOT}/${PROJECT_NAME}.xcodeproj"
BUILD_DIR="${PROJECT_ROOT}/build"
DEVELOPMENT_TEAM="386M76FV3K"
NOTARY_PROFILE="${NOTARY_PROFILE:-Usage4Claude-Arcanii-notarize}"
# Sparkle's sign_update tool. Override via env var if installed elsewhere; the
# build step is skipped (with a hint) when the tool isn't reachable.
SIGN_UPDATE="${SIGN_UPDATE:-/tmp/sparkle-tools/bin/sign_update}"

# Optional: source a gitignored override file so contributors can use their own
# Developer ID team and notary profile without editing this script. See
# scripts/build.config.example for the available variables.
if [ -f "${PROJECT_ROOT}/scripts/build.config" ]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/scripts/build.config"
fi

# xcode-select may point at CommandLineTools; force the full Xcode so archive works.
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

# Defaults
BUILD_CONFIG="Release"
SHOULD_CLEAN=true
VERBOSE=false

# ============================================
# Parse command-line arguments
# ============================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-clean)
            SHOULD_CLEAN=false
            shift
            ;;
        --config)
            BUILD_CONFIG="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --no-clean          Skip the Xcode clean step (clean runs by default)"
            echo "  --config <config>   Build configuration (Release|Debug). Default: Release"
            echo "  --verbose, -v       Show full build log instead of a summary"
            echo "  --help, -h          Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                  # Default: clean + Release build"
            echo "  $0 --no-clean       # Skip clean"
            echo "  $0 --config Debug   # Use Debug configuration"
            echo "  $0 --verbose        # Show full log"
            exit 0
            ;;
        *)
            print_error "Unknown argument: $1"
            echo "Run --help for usage."
            exit 1
            ;;
    esac
done

# ============================================
# Dependency checks
# ============================================
print_header "Checking dependencies"

# xcodebuild
if ! command -v xcodebuild &> /dev/null; then
    print_error "xcodebuild not found. Install Xcode."
    exit 1
fi
print_success "xcodebuild present"

# create-dmg
if ! command -v create-dmg &> /dev/null; then
    print_error "create-dmg not found"
    echo ""
    echo "Install with:"
    echo "  brew install create-dmg"
    exit 1
fi
print_success "create-dmg present"

# Project file
if [ ! -d "$XCODEPROJ" ]; then
    print_error "Project file not found: $XCODEPROJ"
    exit 1
fi
print_success "Project file present"

# ============================================
# Read version
# ============================================
print_header "Reading version"

VERSION=$(xcodebuild -project "$XCODEPROJ" -showBuildSettings | grep MARKETING_VERSION | head -1 | awk '{print $3}')

if [ -z "$VERSION" ]; then
    print_error "Could not read MARKETING_VERSION from the Xcode project"
    exit 1
fi

print_success "Version: $VERSION"

# Output paths
EXPORT_DIR="${BUILD_DIR}/${PROJECT_NAME}-${BUILD_CONFIG}-${VERSION}"
DMG_NAME="${PRODUCT_NAME}-v${VERSION}.dmg"
DMG_PATH="${EXPORT_DIR}/${DMG_NAME}"
LOG_FILE="${EXPORT_DIR}/build.log"
ARCHIVE_PATH="${EXPORT_DIR}/${PROJECT_NAME}.xcarchive"

print_info "Output directory: $EXPORT_DIR"
print_info "DMG filename: $DMG_NAME"

if [ "$VERBOSE" = false ]; then
    print_info "Full log: $LOG_FILE"
fi

mkdir -p "$EXPORT_DIR"

# Truncate the log when running in summary mode
if [ "$VERBOSE" = false ]; then
    > "$LOG_FILE"
fi

# ============================================
# Clean
# ============================================
if [ "$SHOULD_CLEAN" = true ]; then
    print_header "Cleaning build"

    if [ "$VERBOSE" = true ]; then
        xcodebuild clean \
            -project "$XCODEPROJ" \
            -scheme "$SCHEME_NAME" \
            -configuration "$BUILD_CONFIG" \
            -destination "generic/platform=macOS,name=Any Mac"
    else
        print_info "Cleaning..."
        xcodebuild clean \
            -project "$XCODEPROJ" \
            -scheme "$SCHEME_NAME" \
            -configuration "$BUILD_CONFIG" \
            -destination "generic/platform=macOS,name=Any Mac" \
            >> "$LOG_FILE" 2>&1
    fi

    print_success "Clean done"
else
    print_info "Skipping clean step"
fi

# ============================================
# Archive (compile + package)
# ============================================
print_header "Archive (compile + package)"

# Remove any prior archive
if [ -d "$ARCHIVE_PATH" ]; then
    print_info "Removing previous archive"
    rm -rf "$ARCHIVE_PATH"
fi

print_info "Starting compile..."
print_info "Configuration: $BUILD_CONFIG"
print_info "Target: Any Mac (Universal Binary)"

# Use the project's automatic signing for both Debug and Release. The export
# step (via ExportOptions.plist `method = developer-id`) re-signs the Release
# archive with the Developer ID Application identity. Manual signing here used
# to be the path, but adding the App Groups capability for the widget broke it
# (App Groups + Manual style requires a pre-issued provisioning profile per
# bundle ID; Automatic + -allowProvisioningUpdates lets Xcode auto-generate).
ARCHIVE_SIGN_ARGS=(
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
)

if [ "$VERBOSE" = true ]; then
    # Verbose mode: stream xcodebuild output
    xcodebuild archive \
        -project "$XCODEPROJ" \
        -scheme "$SCHEME_NAME" \
        -configuration "$BUILD_CONFIG" \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS,name=Any Mac" \
        -allowProvisioningUpdates \
        "${ARCHIVE_SIGN_ARGS[@]}"
    ARCHIVE_RESULT=$?
else
    # Summary mode: only show progress
    print_info "Compiling, please wait... (typically 1-2 minutes)"
    xcodebuild archive \
        -project "$XCODEPROJ" \
        -scheme "$SCHEME_NAME" \
        -configuration "$BUILD_CONFIG" \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS,name=Any Mac" \
        -allowProvisioningUpdates \
        "${ARCHIVE_SIGN_ARGS[@]}" \
        >> "$LOG_FILE" 2>&1
    ARCHIVE_RESULT=$?
fi

if [ $ARCHIVE_RESULT -ne 0 ] || [ ! -d "$ARCHIVE_PATH" ]; then
    print_error "Archive failed"
    if [ "$VERBOSE" = false ]; then
        print_info "Last 20 lines of log:"
        echo ""
        tail -n 20 "$LOG_FILE"
        echo ""
        print_info "Full log: $LOG_FILE"
    fi
    exit 1
fi

print_success "Archive complete"

# ============================================
# Export (extract .app from archive)
# ============================================
print_header "Export (.app)"

# Release exports use developer-id (for distribution + notarization);
# Debug uses mac-application (development signing).
if [ "$BUILD_CONFIG" = "Release" ]; then
    EXPORT_METHOD="developer-id"
else
    EXPORT_METHOD="mac-application"
fi

EXPORT_OPTIONS_PLIST="${EXPORT_DIR}/ExportOptions.plist"
cat > "$EXPORT_OPTIONS_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>${EXPORT_METHOD}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>${DEVELOPMENT_TEAM}</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
EOF

print_info "Exporting to: $EXPORT_DIR"

if [ "$VERBOSE" = true ]; then
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
        -allowProvisioningUpdates
    EXPORT_RESULT=$?
else
    print_info "Exporting..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
        -allowProvisioningUpdates \
        >> "$LOG_FILE" 2>&1
    EXPORT_RESULT=$?
fi

if [ $EXPORT_RESULT -ne 0 ] || [ ! -d "${EXPORT_DIR}/${PRODUCT_NAME}.app" ]; then
    print_error "Export failed"
    if [ "$VERBOSE" = false ]; then
        print_info "Last 20 lines of log:"
        echo ""
        tail -n 20 "$LOG_FILE"
        echo ""
        print_info "Full log: $LOG_FILE"
    fi
    exit 1
fi

print_success "Export complete: ${EXPORT_DIR}/${PRODUCT_NAME}.app"

# ============================================
# Create DMG
# ============================================
print_header "Creating DMG installer"

# Remove any prior DMG
if [ -f "$DMG_PATH" ]; then
    print_info "Removing previous DMG: $DMG_PATH"
    rm -f "$DMG_PATH"
fi

# DMG icon (optional)
DMG_ICON="${PROJECT_ROOT}/docs/images/DmgIcon.icns"
if [ ! -f "$DMG_ICON" ]; then
    print_warning "DMG icon not found: $DMG_ICON"
    print_info "Creating DMG without a custom icon"
    VOLICON_OPTION=""
else
    VOLICON_OPTION="--volicon ${DMG_ICON}"
fi

cd "$EXPORT_DIR"

if [ "$VERBOSE" = true ]; then
    print_info "Creating DMG: $DMG_NAME"
    create-dmg \
      --volname "${PRODUCT_NAME}-${VERSION}" \
      ${VOLICON_OPTION} \
      --window-pos 200 120 \
      --window-size 600 500 \
      --icon-size 128 \
      --icon "${PRODUCT_NAME}.app" 175 190 \
      --hide-extension "${PRODUCT_NAME}.app" \
      --app-drop-link 425 190 \
      "$DMG_NAME" \
      "${PRODUCT_NAME}.app" 2>&1 | grep -v "Failed running AppleScript" || true
    DMG_RESULT=$?
else
    print_info "Creating DMG..."
    create-dmg \
      --volname "${PRODUCT_NAME}-${VERSION}" \
      ${VOLICON_OPTION} \
      --window-pos 200 120 \
      --window-size 600 500 \
      --icon-size 128 \
      --icon "${PRODUCT_NAME}.app" 175 190 \
      --hide-extension "${PRODUCT_NAME}.app" \
      --app-drop-link 425 190 \
      "$DMG_NAME" \
      "${PRODUCT_NAME}.app" \
      >> "$LOG_FILE" 2>&1
    DMG_RESULT=$?
fi

set -e

# Verify the DMG actually exists
if [ ! -f "$DMG_PATH" ]; then
    print_error "DMG creation failed"
    if [ "$VERBOSE" = false ]; then
        print_info "Last 20 lines of log:"
        echo ""
        tail -n 20 "$LOG_FILE"
        echo ""
        print_info "Full log: $LOG_FILE"
    fi
    exit 1
fi

if [ $DMG_RESULT -ne 0 ]; then
    if [ "$VERBOSE" = true ]; then
        print_warning "create-dmg emitted warnings, but the DMG was produced"
    fi
fi

print_success "DMG created: $DMG_PATH"

# ============================================
# Notarize — Release builds only
# ============================================
NOTARIZED=false
if [ "$BUILD_CONFIG" = "Release" ]; then
    print_header "Notarizing DMG"

    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        print_info "Submitting to Apple notary service (profile: $NOTARY_PROFILE; usually a few minutes)..."
        # notarytool submit --wait exits 0 only when status is Accepted; non-zero otherwise.
        # (Don't pipe to grep — notarytool's \r progress updates corrupt line-based parsing.)
        if xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait >> "$LOG_FILE" 2>&1; then
            print_success "Notarization accepted"
            print_info "Stapling ticket to DMG..."
            if xcrun stapler staple "$DMG_PATH" >> "$LOG_FILE" 2>&1; then
                print_success "Staple complete"
                NOTARIZED=true
            else
                print_warning "Staple failed; DMG is still notarized but first launch will require network access"
            fi
        else
            print_error "Notarization failed — see log: $LOG_FILE"
            print_info "Use 'xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE' to see details"
        fi
    else
        print_warning "notarytool keychain profile '$NOTARY_PROFILE' not found; skipping notarization"
        echo ""
        print_info "First-time setup (one-off) — generate an app-specific password at appleid.apple.com, then:"
        echo "    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
        echo "      --apple-id <your-apple-id-email> \\"
        echo "      --team-id $DEVELOPMENT_TEAM \\"
        echo "      --password <app-specific-password>"
        echo ""
        print_info "(Or set the NOTARY_PROFILE env var to point at an existing profile)"
    fi
fi

# ============================================
# Sparkle EdDSA signature for the appcast — Release only, after notarization.
# Emits a copy-pasteable <enclosure ...> line for appcast.xml. Signing is keyed
# on the Sparkle private key stored in the user's login keychain (set up once
# via `generate_keys`). Without that key, sign_update fails fast.
# ============================================
if [ "$BUILD_CONFIG" = "Release" ] && [ "$NOTARIZED" = true ]; then
    print_header "Sparkle signature"

    if [ ! -x "$SIGN_UPDATE" ]; then
        print_warning "sign_update not found ($SIGN_UPDATE); skipping Sparkle signing"
        print_info "Download Sparkle tools: https://github.com/sparkle-project/Sparkle/releases"
        print_info "Or set the SIGN_UPDATE env var to the path of an installed sign_update"
    else
        SIGN_OUTPUT="$($SIGN_UPDATE "$DMG_PATH" 2>&1)" || true
        if [[ "$SIGN_OUTPUT" == *"sparkle:edSignature="* ]]; then
            print_success "Sparkle signature generated"
            DMG_FILENAME="$(basename "$DMG_PATH")"
            ENCLOSURE_URL="https://github.com/arcanii/Usage4Claude-Arcanii/releases/download/v${VERSION}/${DMG_FILENAME}"
            echo ""
            print_info "Paste the following into appcast.xml as the new <enclosure ...>:"
            echo ""
            echo "    <enclosure"
            echo "        url=\"${ENCLOSURE_URL}\""
            echo "        ${SIGN_OUTPUT}"
            echo "        type=\"application/octet-stream\"/>"
            echo ""
            print_info "(version=${VERSION}, build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${EXPORT_DIR}/${PRODUCT_NAME}.app/Contents/Info.plist" 2>/dev/null || echo '?'))"
        else
            print_error "Sparkle signing failed: $SIGN_OUTPUT"
        fi
    fi
fi

# ============================================
# Cleanup
# ============================================
print_header "Cleaning up temp files"

rm -f "$EXPORT_OPTIONS_PLIST"
rm -rf "$ARCHIVE_PATH"

print_success "Cleanup done"

# ============================================
# Summary
# ============================================
print_header "Build complete 🎉"

echo ""
print_success "Version: $VERSION"
print_success "Configuration: $BUILD_CONFIG"
print_success "Output directory: $EXPORT_DIR"
echo ""
print_info "Artifacts:"
echo "  📦 App: ${EXPORT_DIR}/${PRODUCT_NAME}.app"
echo "  💿 DMG: ${DMG_PATH}"
if [ "$BUILD_CONFIG" = "Release" ]; then
    if [ "$NOTARIZED" = true ]; then
        echo "  ✅ Notarized + stapled (ready to distribute)"
    else
        echo "  ⚠️  Not notarized (users must right-click → Open on first launch)"
    fi
fi
echo ""

DMG_SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')
print_info "DMG size: $DMG_SIZE"

echo ""
print_success "All done!"
echo ""
