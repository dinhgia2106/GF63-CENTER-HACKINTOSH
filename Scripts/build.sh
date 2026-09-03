#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DERIVED_DIR="$PROJECT_DIR/build/DerivedData"
PRODUCT_DIR="$PROJECT_DIR/build/Products"

xcodebuild -quiet \
  -project "$PROJECT_DIR/R3Control.xcodeproj" \
  -scheme R3Control \
  -configuration Release \
  -derivedDataPath "$DERIVED_DIR/App" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build

xcodebuild -quiet \
  -project "$PROJECT_DIR/R3EC.xcodeproj" \
  -scheme R3EC \
  -configuration Release \
  -derivedDataPath "$DERIVED_DIR/Kext" \
  CODE_SIGNING_ALLOWED=NO \
  build

mkdir -p "$PRODUCT_DIR"
ditto "$DERIVED_DIR/App/Build/Products/Release/R3Control.app" "$PRODUCT_DIR/R3Control.app"
ditto "$DERIVED_DIR/Kext/Build/Products/Release/R3EC.kext" "$PRODUCT_DIR/R3EC.kext"

clang -Wall -Wextra -Werror -std=c11 \
  "$PROJECT_DIR/Scripts/r3ec-smoke.c" \
  "$PROJECT_DIR/R3Control/SMCBridge.c" \
  -framework IOKit \
  -framework CoreFoundation \
  -o "$PROJECT_DIR/build/r3ec-smoke"

print "Built:"
print "  $PRODUCT_DIR/R3Control.app"
print "  $PRODUCT_DIR/R3EC.kext"
print "  $PROJECT_DIR/build/r3ec-smoke"
