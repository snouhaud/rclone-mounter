#!/bin/bash
# Regression tests for the rclone mounter plugin. No network, no real mounts:
# rclone is replaced by a fake binary on PATH.
#   tests/run.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/rclone-mounts.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [[ -n ${2:-} ]] && printf '       %s\n' "$2"; }
check() { # check <description> <jq filter that must be true> <json>
  if jq -e "$2" <<<"$3" >/dev/null 2>&1; then ok "$1"; else ko "$1" "$3"; fi
}

# --- Fake environment --------------------------------------------------------
# bin-full: every tool, with a fake rclone. bin-*: same minus one tool.
make_bin() {
  local dir="$WORK/$1"; shift
  mkdir -p "$dir"
  local tool
  for tool in bash jq awk head tail tr cut grep sed mountpoint mkdir rmdir rm cat printf env timeout sleep setsid; do
    local real; real=$(command -v "$tool") && ln -sf "$real" "$dir/$tool"
  done
  for tool in "$@"; do
    case "$tool" in
      rclone) cp "$WORK/fake-rclone" "$dir/rclone"; chmod +x "$dir/rclone" ;;
      fusermount3) printf '#!/bin/sh\nexit 0\n' >"$dir/fusermount3"; chmod +x "$dir/fusermount3" ;;
      secret-tool) printf '#!/bin/sh\nexit 1\n' >"$dir/secret-tool"; chmod +x "$dir/secret-tool" ;;
      zenity) printf '#!/bin/sh\nexit 1\n' >"$dir/zenity"; chmod +x "$dir/zenity" ;;
    esac
  done
}

CONFIG="$WORK/rclone.conf"
REMOTES="$WORK/remotes.txt"
cat >"$WORK/fake-rclone" <<FAKE
#!/bin/bash
case "\$1 \$2" in
  "config file") printf 'Configuration file is stored at:\n%s\n' "$CONFIG" ;;
  listremotes*)
    [[ -f "$WORK/locked" ]] && { echo "config encrypted" >&2; exit 1; }
    cat "$REMOTES" ;;
  *) exit 1 ;;
esac
FAKE

make_bin bin-full rclone fusermount3 secret-tool zenity
make_bin bin-no-rclone fusermount3 secret-tool zenity
make_bin bin-no-fuse rclone secret-tool zenity
make_bin bin-no-keyring rclone fusermount3

run() { # run <bin-dir> <args...>
  local bin="$WORK/$1"; shift
  HOME="$WORK/home" PATH="$bin" RCLONE_CONFIG="$CONFIG" bash "$HELPER" "$@"
}
mkdir -p "$WORK/home"
BASE="$WORK/mnt"

echo "manifest and catalogs"
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$ROOT" >/dev/null 2>&1 && ok "omarchy plugin validate" || ko "omarchy plugin validate"
fi
for f in "$ROOT"/i18n/*.json "$ROOT/manifest.json"; do
  jq -e . "$f" >/dev/null 2>&1 && ok "valid JSON: ${f#"$ROOT"/}" || ko "valid JSON: ${f#"$ROOT"/}"
done
missing=$(jq -rn --slurpfile en "$ROOT/i18n/en.json" --slurpfile fr "$ROOT/i18n/fr.json" \
  '(($en[0] | keys) - ($fr[0] | keys)) + (($fr[0] | keys) - ($en[0] | keys)) | join(", ")')
[[ -z $missing ]] && ok "en.json and fr.json have the same keys" || ko "en.json and fr.json have the same keys" "$missing"

echo "plain-text rendering (markup-shaped input must never be interpreted)"
for qml in "$ROOT"/*.qml; do
  texts=$(grep -cE '^\s*Text \{' "$qml")
  plain=$(grep -cE 'textFormat: Text\.PlainText' "$qml")
  if (( plain >= texts )); then ok "${qml##*/}: $texts Text items, all PlainText"
  else ko "${qml##*/}: every Text sets textFormat: Text.PlainText" "$texts Text, $plain PlainText"; fi
done

echo "prerequisites"
: >"$CONFIG"
printf 'gdrive:  drive\n' >"$REMOTES"
check "rclone missing is reported" '.issues == ["rcloneMissing"]' "$(run bin-no-rclone status "$BASE" '' '')"
check "empty config is reported" '.issues == ["noConfig"]' "$(run bin-full status "$BASE" '' '')"
rm -f "$CONFIG"
check "missing config is reported" '.issues == ["noConfig"] and (.configPath | endswith("rclone.conf"))' "$(run bin-full status "$BASE" '' '')"
echo "[gdrive]" >"$CONFIG"
check "fuse missing is reported, remotes still listed" '.issues == ["fuseMissing"] and (.remotes | length) == 1' "$(run bin-no-fuse status "$BASE" '' '')"
check "mount refuses without fuse" '.ok == false and .error == "fuseMissing"' "$(run bin-no-fuse mount "$BASE" gdrive full '' 0)"
: >"$REMOTES"
check "config without remotes is reported" '.issues == ["noRemotes"]' "$(run bin-full status "$BASE" '' '')"
touch "$WORK/locked"
check "locked config without keyring tools is reported" \
  '.locked == true and (.issues | index("secretToolMissing")) and (.issues | index("zenityMissing"))' \
  "$(run bin-no-keyring status "$BASE" '' '')"
check "unlock refuses without secret-tool" '.error == "secretToolMissing"' "$(run bin-no-keyring unlock)"
rm -f "$WORK/locked"

echo "listing and settings"
printf 'gdrive:  drive\nnas:     sftp\nphotos:  alias\n' >"$REMOTES"
out=$(run bin-full status "$BASE" ' nas , x' 'photos')
check "healthy status has no issues" '.ok and .issues == [] and .locked == false' "$out"
check "excluded remotes are hidden (spaces trimmed)" '[.remotes[].name] == ["gdrive", "photos"]' "$out"
check "read-only remotes are flagged" '[.remotes[] | select(.forcedReadOnly) | .name] == ["photos"]' "$out"
check "types are reported" '.remotes[0].type == "drive"' "$out"
check "~ in the mount folder expands to HOME" ".base == \"$WORK/home/mnt\"" "$(run bin-full status '~/mnt' '' '')"

echo "input validation"
printf 'gdrive:  drive\n<img src=https://example.invalid/t>:  drive\n-rf:  local\n../x:  local\n' >"$REMOTES"
check "markup-shaped and unsafe remote names are dropped" '[.remotes[].name] == ["gdrive"]' "$(run bin-full status "$BASE" '' '')"
check "relative mount folder is refused" '.error == "invalidBase"' "$(run bin-full status relative '' '')"
check "path traversal name is refused" '.error == "invalidName"' "$(run bin-full mount "$BASE" '../etc' full '' 0)"
check "option-like name is refused" '.error == "invalidName"' "$(run bin-full unmount "$BASE" '-uz')"
check "markup name is refused" '.error == "invalidName"' "$(run bin-full mount "$BASE" '<b>x</b>' full '' 0)"
check "unknown mode is refused" '.error == "invalidMode"' "$(run bin-full mount "$BASE" gdrive turbo '' 0)"
check "unknown remote is refused" '.error == "unknownRemote"' "$(run bin-full mount "$BASE" nope full '' 0)"
check "unknown command is refused" '.error == "usage"' "$(run bin-full rm -rf /)"
check "unmounting something not mounted is a no-op" '.ok and .already' "$(run bin-full unmount "$BASE" gdrive)"

echo "keyring password (forget)"
make_bin bin-keyring rclone fusermount3 zenity
cat >"$WORK/bin-keyring/secret-tool" <<KEYRING
#!/bin/bash
# Stateful fake: the stored password lives in $WORK/secret.
case "\$1" in
  lookup) cat "$WORK/secret" 2>/dev/null ;;
  clear) rm -f "$WORK/secret" ;;
  store) cat >"$WORK/secret" ;;
esac
KEYRING
chmod +x "$WORK/bin-keyring/secret-tool"
printf 'gdrive:  drive\n' >"$REMOTES"
echo hunter2 >"$WORK/secret"
check "a stored, working password is reported" '.keyringStored == true and .locked == false' "$(run bin-keyring status "$BASE" '' '')"
touch "$WORK/locked"
check "a stored password that fails is reported as badPassword" \
  '.locked == true and .keyringStored == true and (.issues | index("badPassword"))' "$(run bin-keyring status "$BASE" '' '')"
check "forget deletes the password" '.ok == true and .action == "forget"' "$(run bin-keyring forget)"
[[ ! -e $WORK/secret ]] && ok "the keyring entry is gone" || ko "the keyring entry is gone"
check "after forget the config is locked, nothing stored" \
  '.locked == true and .keyringStored == false and ((.issues | index("badPassword")) | not)' "$(run bin-keyring status "$BASE" '' '')"
check "forget refuses without secret-tool" '.error == "secretToolMissing"' "$(run bin-no-keyring forget)"
rm -f "$WORK/locked"
check "no stored password on a plain config" '.keyringStored == false and .locked == false' "$(run bin-keyring status "$BASE" '' '')"

echo "language (English by default, French when Omarchy or the system is French)"
if command -v node >/dev/null 2>&1; then
  node_out=$(node -e '
    const fs = require("fs");
    const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\s*/, "");
    const L = new Function(src + "; return { resolve, base, pluralCategory, normalize };")();
    const cases = [
      ["Omarchy fr wins over an English system", L.resolve("fr", "", "", "en_US.UTF-8"), "fr"],
      ["Omarchy en wins over a French system", L.resolve("en", "", "", "fr_FR.UTF-8"), "en"],
      ["no Omarchy language: LANG fr_FR.UTF-8 gives fr-FR (fr.json via its base)", L.resolve("", "", "", "fr_FR.UTF-8"), "fr-FR"],
      ["LC_ALL overrides LANG", L.resolve("", "fr_CA.UTF-8", "", "en_US.UTF-8"), "fr-CA"],
      ["LC_MESSAGES overrides LANG", L.resolve("", "", "fr_BE@euro", "en_US.UTF-8"), "fr-BE"],
      ["nothing set gives en", L.resolve("", "", "", ""), "en"],
      ["C locale gives en", L.resolve("", "", "", "C.UTF-8"), "en"],
      ["garbage Omarchy value falls through to LANG", L.resolve("<b>", "", "", "fr_FR.UTF-8"), "fr-FR"],
      ["base of fr-CA is fr", L.base("fr-CA"), "fr"],
      ["fr plural: 0 is one", L.pluralCategory("fr", 0), "one"],
      ["fr plural: 2 is other", L.pluralCategory("fr", 2), "other"],
      ["en plural: 0 is other", L.pluralCategory("en", 0), "other"],
      ["en plural: 1 is one", L.pluralCategory("en", 1), "one"],
    ];
    for (const [name, got, want] of cases)
      console.log((got === want ? "ok" : "FAIL") + "\t" + name + (got === want ? "" : " (got " + got + ")"));
  ' "$ROOT/Language.js")
  while IFS=$'\t' read -r status name; do
    [[ $status == ok ]] && ok "$name" || ko "$name"
  done <<<"$node_out"
else
  echo "  skip Language.js tests (node not installed)"
fi

make_bin bin-lang rclone fusermount3 secret-tool zenity
rm -f "$WORK/bin-lang/mountpoint"  # a symlink to the real binary: never write through it
printf '#!/bin/sh\nexit 0\n' >"$WORK/bin-lang/mountpoint"; chmod +x "$WORK/bin-lang/mountpoint"
printf '#!/bin/sh\nprintf "%%s" "$2" >"%s"\n' "$WORK/notified" >"$WORK/bin-lang/notify-send"; chmod +x "$WORK/bin-lang/notify-send"
printf 'gdrive:  drive\n' >"$REMOTES"
notified() { # notified <omarchy language or -> <LANG>
  rm -f "$WORK/notified" "$WORK/language"
  [[ $1 != - ]] && echo "$1" >"$WORK/language"
  HOME="$WORK/home" PATH="$WORK/bin-lang" RCLONE_CONFIG="$CONFIG" LANG="$2" LC_ALL= LC_MESSAGES= \
    OMARCHY_LANGUAGE_FILE="$WORK/language" bash "$HELPER" unmount "$BASE" gdrive >/dev/null
  cat "$WORK/notified" 2>/dev/null
}
[[ $(notified - en_US.UTF-8) == "Unmounted gdrive" ]] && ok "helper: English by default" || ko "helper: English by default" "$(notified - en_US.UTF-8)"
[[ $(notified - fr_FR.UTF-8) == "gdrive démonté" ]] && ok "helper: French from LANG" || ko "helper: French from LANG" "$(notified - fr_FR.UTF-8)"
[[ $(notified fr en_US.UTF-8) == "gdrive démonté" ]] && ok "helper: French from the Omarchy language" || ko "helper: French from the Omarchy language"
[[ $(notified en fr_FR.UTF-8) == "Unmounted gdrive" ]] && ok "helper: Omarchy language wins over LANG" || ko "helper: Omarchy language wins over LANG"
[[ $(notified - de_DE.UTF-8) == "Unmounted gdrive" ]] && ok "helper: untranslated language falls back to English" || ko "helper: untranslated language falls back to English"

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
