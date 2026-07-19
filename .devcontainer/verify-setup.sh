#!/bin/bash

echo "=============================================="
echo "   fl_muse_brainflow_MVP  —  Setup Verification"
echo "=============================================="
echo ""

# Colors (optional, works in most terminals)
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"   # No Color

print_check() {
    local label="$1"
    local state="$2"
    if [ "$state" = "ok" ]; then
        printf "  ${GREEN}[x]${NC} %-35s\n" "$label"
    else
        printf "  ${RED}[ ]${NC} %-35s\n" "$label"
    fi
}

# Portable command existence check (sh/bash/zsh compatible)
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# =====================
# LINUX / DESKTOP
# =====================
echo "📱 Linux / Desktop"
echo "----------------------------------------------"

if has_cmd flutter; then
    print_check "Flutter" "ok"
else
    print_check "Flutter" "missing"
fi

if has_cmd rustc; then
    print_check "Rust (rustc)" "ok"
else
    print_check "Rust (rustc)" "missing"
fi

if has_cmd cargo; then
    print_check "Cargo" "ok"
else
    print_check "Cargo" "missing"
fi

if has_cmd flutter_rust_bridge_codegen; then
    print_check "flutter_rust_bridge_codegen" "ok"
else
    print_check "flutter_rust_bridge_codegen" "missing"
fi

echo ""

# =====================
# ANDROID
# =====================
echo "🤖 Android"
echo "----------------------------------------------"

if has_cmd java && java -version 2>&1 | grep -q "21"; then
    print_check "Java 21" "ok"
else
    print_check "Java 21" "missing/wrong version"
fi

if [ -n "${ANDROID_HOME}" ] && [ -d "${ANDROID_HOME}" ]; then
    print_check "ANDROID_HOME set + directory exists" "ok"
else
    print_check "ANDROID_HOME" "missing"
fi

if [ -x "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ]; then
    print_check "cmdline-tools + sdkmanager" "ok"
else
    print_check "cmdline-tools + sdkmanager" "missing"
fi

if [ -d "${ANDROID_HOME}/platform-tools" ] && [ -x "${ANDROID_HOME}/platform-tools/adb" ]; then
    print_check "platform-tools (adb)" "ok"
else
    print_check "platform-tools (adb)" "missing"
fi

if [ -d "${ANDROID_HOME}/build-tools/34.0.0" ]; then
    print_check "build-tools;34.0.0" "ok"
else
    print_check "build-tools;34.0.0" "missing"
fi

if [ -d "${ANDROID_HOME}/platforms/android-34" ]; then
    print_check "platforms;android-34" "ok"
else
    print_check "platforms;android-34" "missing"
fi

if [ -d "${ANDROID_HOME}/ndk/28.2.13676358" ]; then
    print_check "NDK 28.2.13676358" "ok"
else
    print_check "NDK 28.2.13676358" "missing"
fi

if rustup target list --installed 2>/dev/null | grep -q "aarch64-linux-android"; then
    print_check "Rust target: aarch64-linux-android   (64bit)" "ok"
else
    print_check "Rust target: aarch64-linux-android   (64bit)" "missing"
fi

if rustup target list --installed 2>/dev/null | grep -q "armv7-linux-androideabi"; then
    print_check "Rust target: armv7-linux-androideabi (32bit)" "ok"
else
    print_check "Rust target: armv7-linux-androideabi (32bit)" "missing"
fi

if has_cmd cargo-ndk; then
    print_check "cargo-ndk" "ok"
else
    print_check "cargo-ndk" "missing"
fi

echo ""

# =====================
# WINDOWS (future)
# =====================
echo "🪟 Windows (placeholder / future)"
echo "----------------------------------------------"
print_check "Windows toolchain (not yet implemented)" "missing"
echo ""

echo "=============================================="
echo "Tip: Run 'flutter doctor -v' for the official Flutter report."
echo "=============================================="
