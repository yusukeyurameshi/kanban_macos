#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/.build/release"
DIST="$ROOT/dist"
APP="$DIST/Meu Kanban.app"

cd "$ROOT"
swift build -c release

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "VERSION deve usar o formato x.y.z"
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/MeuKanban" "$APP/Contents/MacOS/MeuKanban"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
cp -R "$BUILD/MeuKanban_MeuKanban.bundle" "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"

rm -f "$DIST/Meu-Kanban-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/Meu-Kanban-macOS.zip"
print "Pacote criado: $DIST/Meu-Kanban-macOS.zip"
