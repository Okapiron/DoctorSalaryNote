#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/DoctorSalaryNote.xcodeproj"
EXPORT_OPTIONS_PATH="$ROOT_DIR/tools/ExportOptions-TestFlight.plist"

SCHEME="DoctorSalaryNote"
TEAM_ID="2WG3Z522JL"
ASC_KEY_ID="${ASC_KEY_ID:-VL7Q8S9YXC}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-7ef8fd2b-6536-4742-8f1d-7d3aece815c4}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "App Store Connect APIキーが見つかりません: $ASC_KEY_PATH" >&2
  exit 1
fi

if [[ ! -f "$EXPORT_OPTIONS_PATH" ]]; then
  echo "ExportOptions plistが見つかりません: $EXPORT_OPTIONS_PATH" >&2
  exit 1
fi

PROJECT_BUILD_NUMBER="$({
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -showBuildSettings 2>/dev/null
} | awk -F ' = ' '/ CURRENT_PROJECT_VERSION = / { print $2; exit }')"

BUILD_NUMBER="${1:-$PROJECT_BUILD_NUMBER}"
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Build Numberには正の整数を指定してください。" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d /private/tmp/DoctorSalaryNote-TestFlight.XXXXXX)"
ARCHIVE_PATH="$WORK_DIR/DoctorSalaryNote.xcarchive"
EXPORT_PATH="$WORK_DIR/export"

echo "Build $BUILD_NUMBER をArchiveします。"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  archive

echo "Build $BUILD_NUMBER をTestFlightへアップロードします。"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "TestFlightへの送信が完了しました。"
echo "Archiveとログ: $WORK_DIR"
