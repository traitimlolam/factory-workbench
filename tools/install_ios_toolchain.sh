#!/usr/bin/env bash
set -euo pipefail
THEOS_COMMIT=dd5c14bb9d91311e221d51b5bfb8c9e5948156db
SDK_COMMIT=0222fd5413cf4b9af096f37b4621afa2688572f7
SDK_NAME=iPhoneOS16.5.sdk
export THEOS="$RUNNER_TEMP/theos"
git clone https://github.com/theos/theos.git "$THEOS"
git -C "$THEOS" checkout --detach "$THEOS_COMMIT"
test "$(git -C "$THEOS" rev-parse HEAD)" = "$THEOS_COMMIT"
git -C "$THEOS" submodule update --init --recursive
git clone https://github.com/theos/sdks.git "$RUNNER_TEMP/theos-sdks"
git -C "$RUNNER_TEMP/theos-sdks" checkout --detach "$SDK_COMMIT"
test "$(git -C "$RUNNER_TEMP/theos-sdks" rev-parse HEAD)" = "$SDK_COMMIT"
mkdir -p "$THEOS/sdks"
cp -R "$RUNNER_TEMP/theos-sdks/$SDK_NAME" "$THEOS/sdks/$SDK_NAME"
test -d "$THEOS/sdks/$SDK_NAME"
printf 'THEOS=%s\n' "$THEOS" >> "$GITHUB_ENV"
brew install dpkg ldid
