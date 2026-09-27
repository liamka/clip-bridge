#!/bin/zsh
# Сборка ClipBridge.app и ClipBridge.dmg без Xcode.
#
#   scripts/build.sh            — быстрая сборка под текущую архитектуру (для проверки)
#   scripts/build.sh --release  — универсальная сборка arm64 + x86_64 и .dmg для раздачи
#
# Подпись: SIGN_IDENTITY="Developer ID Application: …" — подпись для раздачи.
# Без переменной — ad-hoc (запуск у получателя через «Всё равно открыть»).
set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT"
APP=ClipBridge
DIST="$ROOT/dist"
BUNDLE="$DIST/$APP.app"
IDENTITY=${SIGN_IDENTITY:--}

release=false
[[ ${1:-} == --release ]] && release=true

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

if $release; then
  for arch in arm64 x86_64; do
    swift build -c release --product $APP --triple $arch-apple-macosx13.0
  done
  lipo -create \
    .build/arm64-apple-macosx/release/$APP \
    .build/x86_64-apple-macosx/release/$APP \
    -output "$BUNDLE/Contents/MacOS/$APP"
else
  swift build -c release --product $APP
  cp "$(swift build -c release --show-bin-path)/$APP" "$BUNDLE/Contents/MacOS/$APP"
fi

cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/"

codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$BUNDLE"
codesign --verify --strict "$BUNDLE"
lipo -info "$BUNDLE/Contents/MacOS/$APP"

if $release; then
  STAGE="$DIST/dmg"
  rm -rf "$STAGE" "$DIST/$APP.dmg"
  mkdir -p "$STAGE"
  cp -R "$BUNDLE" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  cp Resources/INSTALL.txt "$STAGE/Как установить.txt"
  hdiutil create -volname "$APP" -srcfolder "$STAGE" -format UDZO -ov "$DIST/$APP.dmg" >/dev/null
  rm -rf "$STAGE"
  [[ $IDENTITY != - ]] && codesign --force --sign "$IDENTITY" "$DIST/$APP.dmg"
  echo "Готово: $DIST/$APP.dmg ($(du -h "$DIST/$APP.dmg" | cut -f1))"
else
  echo "Готово: $BUNDLE"
fi
