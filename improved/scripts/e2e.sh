#!/bin/zsh
# Живая проверка захвата буфера (TEST.md, часть B).
# Запускает собранный dist/ClipBridge.app с временной папкой истории, копирует из трёх
# приложений, пишет «пароль» и «свою» запись, завершает приложение и проверяет history.sqlite.
# На время проверки активирует TextEdit, Safari и Terminal. После себя убирает всё:
# закрывает приложения, которые открыла сама, возвращает буфер, фокус и настоящий ClipBridge,
# удаляет временную историю.
set -euo pipefail

ROOT=${0:A:h:h}
APP="$ROOT/dist/ClipBridge.app"
DATA=$(mktemp -d /tmp/clipbridge-e2e.XXXXXX)
SAVED=$(pbpaste 2>/dev/null || true)
TEST_APPS=(com.apple.TextEdit com.apple.Safari com.apple.Terminal)

is_running() { [[ $(osascript -e "application id \"$1\" is running") == true ]]; }

# Что было до проверки.
typeset -a STARTED_BY_US
for id in $TEST_APPS; do is_running $id || STARTED_BY_US+=$id; done
FRONT=$(osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true' 2>/dev/null || true)
CLIPBRIDGE_WAS_RUNNING=false
is_running app.clipbridge.mac && CLIPBRIDGE_WAS_RUNNING=true

cleanup() {
  osascript -e 'tell application id "app.clipbridge.mac" to quit' >/dev/null 2>&1 || true
  for id in $STARTED_BY_US; do
    osascript -e "tell application id \"$id\" to quit saving no" >/dev/null 2>&1 || true
  done
  print -rn -- "$SAVED" | pbcopy
  rm -rf "$DATA"
  if $CLIPBRIDGE_WAS_RUNNING; then open "$APP"; fi
  if [[ -n $FRONT ]]; then osascript -e "tell application id \"$FRONT\" to activate" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

[[ -d $APP ]] || { echo "Нет $APP — сначала scripts/build.sh"; exit 1; }
osascript -e 'tell application id "app.clipbridge.mac" to quit' >/dev/null 2>&1 || true
sleep 1
open -n --env CLIPBRIDGE_DATA_DIR="$DATA" "$APP"
sleep 2

frontmost() { osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true' 2>/dev/null; }

copy_from() { # $1 — bundle id приложения, $2 — текст
  # Активируем, пока приложение действительно не станет активным (холодный старт бывает долгим).
  for i in {1..60}; do
    (( i % 4 == 1 )) && osascript -e "tell application id \"$1\" to activate" >/dev/null 2>&1
    [[ $(frontmost) == "$1" ]] && break
    sleep 0.25
  done
  if [[ $(frontmost) != "$1" ]]; then
    echo "СБОЙ СТЕНДА: $1 не стал активным за 15 с — это не ошибка ClipBridge"
    exit 3
  fi
  sleep 0.5
  print -rn -- "$2" | pbcopy
  sleep 1
}

# Запись в буфер с произвольными типами — через Objective-C мост JXA.
copy_with_type() { # $1 — текст, $2 — дополнительный тип
  osascript -l JavaScript - "$1" "$2" <<'JS' >/dev/null
ObjC.import('AppKit');
function run(argv) {
  const pb = $.NSPasteboard.generalPasteboard;
  pb.clearContents;
  pb.declareTypesOwner($([$.NSPasteboardTypeString, argv[1]]), $());
  pb.setStringForType(argv[0], $.NSPasteboardTypeString);
  pb.setStringForType('', argv[1]);
}
JS
  sleep 1
}

copy_from com.apple.TextEdit "Заметка для контекста из TextEdit"
copy_from com.apple.Safari   "https://developer.apple.com/documentation/appkit/nspasteboard"
copy_from com.apple.Terminal "swift build -c release --product ClipBridge"
copy_with_type "hunter2-secret-password" "org.nspasteboard.ConcealedType"
copy_with_type "# Контекст из буфера обмена (1)" "app.clipbridge.own"

osascript -e 'tell application id "app.clipbridge.mac" to quit'
sleep 1.5

python3 - "$DATA/history.sqlite" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.row_factory = sqlite3.Row
items = [dict(r, sourceName=r["source_name"], sourceBundleID=r["source_bundle_id"])
         for r in db.execute("SELECT * FROM items ORDER BY seq DESC")]
print("history.sqlite:")
for i in items:
    print(f"  [{i['kind']:4}] {i.get('sourceName')!s:10} {i.get('sourceBundleID')!s:26} | {i['text']}")
by_text = {i["text"]: i for i in items}
checks = [
    ("B1 TextEdit → text", by_text.get("Заметка для контекста из TextEdit", {}).get("sourceBundleID") == "com.apple.TextEdit"
        and by_text["Заметка для контекста из TextEdit"]["kind"] == "text"),
    ("B1 Safari → link", by_text.get("https://developer.apple.com/documentation/appkit/nspasteboard", {}).get("sourceBundleID") == "com.apple.Safari"
        and by_text["https://developer.apple.com/documentation/appkit/nspasteboard"]["kind"] == "link"),
    ("B1 Terminal → code", by_text.get("swift build -c release --product ClipBridge", {}).get("sourceBundleID") == "com.apple.Terminal"
        and by_text["swift build -c release --product ClipBridge"]["kind"] == "code"),
    ("B2 пароль не записан", "hunter2-secret-password" not in by_text),
    ("B3 своя запись не записана", "# Контекст из буфера обмена (1)" not in by_text),
    ("B  ровно 3 записи", len(items) == 3),
]
fail = 0
for name, ok in checks:
    print(("ok   " if ok else "FAIL ") + name)
    fail += not ok
sys.exit(1 if fail else 0)
PY
