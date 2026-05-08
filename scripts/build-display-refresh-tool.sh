#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
ROOT_DIR=${SCRIPT_DIR:h}
SOURCE_FILE="$SCRIPT_DIR/refresh-external-display.swift"
OUTPUT_DIR="$ROOT_DIR/build/display-refresh"
OUTPUT_FILE="$OUTPUT_DIR/refresh-external-display"
MODULE_CACHE_DIR="$OUTPUT_DIR/module-cache"
SDK_PATH=$(/usr/bin/xcrun --show-sdk-path)

mkdir -p "$OUTPUT_DIR"
mkdir -p "$MODULE_CACHE_DIR"
/usr/bin/xcrun swiftc \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -parse-as-library \
  -O \
  "$SOURCE_FILE" \
  -o "$OUTPUT_FILE"

echo "Built display refresh tool:"
echo "  $OUTPUT_FILE"
