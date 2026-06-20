#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-SmartSensorBall.xcodeproj}"
SCHEME="${SCHEME:-SmartSensorBall}"
CONFIGURATION="${CONFIGURATION:-Debug}"
MIN_IOS="${MIN_IOS:-15.0}"
DERIVED_DATA_ROOT="${DERIVED_DATA_ROOT:-$PWD/build/compatibility}"

BUILD_SETTINGS_FILE="$DERIVED_DATA_ROOT/build-settings.txt"
GENERIC_DERIVED_DATA="$DERIVED_DATA_ROOT/generic"
ANALYZE_DERIVED_DATA="$DERIVED_DATA_ROOT/analyze"
DESTINATIONS_FILE="$DERIVED_DATA_ROOT/simulator-destinations.txt"

mkdir -p "$DERIVED_DATA_ROOT"

echo "== Xcode version =="
xcodebuild -version

echo "== Check project deployment settings =="
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -showBuildSettings > "$BUILD_SETTINGS_FILE"

DEPLOYMENT_TARGETS="$(awk -F= '
  $1 ~ /^[[:space:]]*IPHONEOS_DEPLOYMENT_TARGET[[:space:]]*$/ {
    value = $2
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    print value
  }
' "$BUILD_SETTINGS_FILE" | tr -d '\r' | sort -u)"
if [ -z "$DEPLOYMENT_TARGETS" ]; then
  echo "No IPHONEOS_DEPLOYMENT_TARGET found in build settings."
  exit 1
fi

if [ "$DEPLOYMENT_TARGETS" != "$MIN_IOS" ]; then
  echo "Expected IPHONEOS_DEPLOYMENT_TARGET=$MIN_IOS, got: $DEPLOYMENT_TARGETS"
  exit 1
fi

DEVICE_FAMILIES="$(awk -F= '
  $1 ~ /^[[:space:]]*TARGETED_DEVICE_FAMILY[[:space:]]*$/ {
    value = $2
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    print value
  }
' "$BUILD_SETTINGS_FILE" | tr -d '\r' | sort -u)"
if [ "$DEVICE_FAMILIES" != "1" ]; then
  echo "Expected TARGETED_DEVICE_FAMILY=1 for iPhone-only support, got: ${DEVICE_FAMILIES:-<empty>}"
  exit 1
fi

if ! grep -Fq ".iOS(.v15)" Package.swift; then
  echo "Expected Package.swift to declare .iOS(.v15)."
  exit 1
fi

echo "Deployment target and package platform are locked to iOS $MIN_IOS."

echo "== List available simulator runtimes =="
xcrun simctl list runtimes

echo "== Generic simulator build =="
rm -rf "$GENERIC_DERIVED_DATA"
xcodebuild clean build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$GENERIC_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CLANG_WARN_UNGUARDED_AVAILABILITY=YES_AGGRESSIVE

APP_PATH="$(find "$GENERIC_DERIVED_DATA/Build/Products" -path "*/${CONFIGURATION}-iphonesimulator/*.app" -type d | sed -n '1p')"
if [ -z "$APP_PATH" ]; then
  echo "No simulator .app found under $GENERIC_DERIVED_DATA."
  exit 1
fi

MINIMUM_OS="$(/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$APP_PATH/Info.plist")"
if [ "$MINIMUM_OS" != "$MIN_IOS" ]; then
  echo "Expected built app MinimumOSVersion=$MIN_IOS, got: $MINIMUM_OS"
  exit 1
fi

echo "Built app MinimumOSVersion is $MINIMUM_OS."

echo "== Static analysis =="
rm -rf "$ANALYZE_DERIVED_DATA"
xcodebuild analyze \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$ANALYZE_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CLANG_WARN_UNGUARDED_AVAILABILITY=YES_AGGRESSIVE

echo "== Select installed iOS simulator devices =="
python3 - <<'PY' > "$DESTINATIONS_FILE"
import json
import re
import subprocess

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j", "devices", "available"]))
by_major = {}

for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue

    major = int(match.group(1))
    minor = int(match.group(2))
    iphones = [
        device for device in devices
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone")
    ]
    if not iphones:
        continue

    current = by_major.get(major)
    candidate = (major, minor, iphones[0]["udid"], iphones[0]["name"])
    if current is None or minor > current[1]:
        by_major[major] = candidate

selected = []
for major in (15, 16, 17):
    if major in by_major:
        selected.append(by_major[major])

if by_major:
    latest = max(by_major.values(), key=lambda item: (item[0], item[1]))
    if latest not in selected:
        selected.append(latest)

for major, minor, udid, name in selected:
    print(f"{major}.{minor}|{udid}|{name}")
PY

if [ ! -s "$DESTINATIONS_FILE" ]; then
  echo "No installed iOS simulator devices were found. Generic simulator build already passed."
  exit 0
fi

while IFS='|' read -r runtime_version udid device_name; do
  echo "== Simulator build on iOS $runtime_version: $device_name ($udid) =="
  RUNTIME_DERIVED_DATA="$DERIVED_DATA_ROOT/runtime-$runtime_version"
  rm -rf "$RUNTIME_DERIVED_DATA"
  xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$RUNTIME_DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CLANG_WARN_UNGUARDED_AVAILABILITY=YES_AGGRESSIVE
done < "$DESTINATIONS_FILE"

echo "iOS compatibility checks passed."
