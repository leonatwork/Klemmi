#!/usr/bin/env bash
# Checks the app's localizations in Resources/<lang>.lproj:
#   - every Localizable.strings / .stringsdict passes `plutil -lint`
#   - every language has exactly the keys of the development language (en)
#   - placeholders (%@, %ld) match en for every key, plural rules have an "other" form
#   - every key used in Sources/ via L10n.tr("…") exists, and every key is used
# Exits non-zero on the first category of problems found.
set -euo pipefail

cd "$(dirname "$0")/.."
BASE="en"
LANGS=(en de fr es it pt-BR nl ja zh-Hans ko)
TABLES=(Localizable.strings Localizable.stringsdict)
fail=0
err() { echo "  ✗ $*"; fail=1; }

# Prints "key<TAB>signature" per top-level key, sorted. The signature is the sorted
# list of placeholders (positional markers stripped) so translations may reorder them.
dump() {
  osascript -l JavaScript - "$1" <<'JS'
ObjC.import('Foundation');
function sig(s) {
  const m = s.match(/%(\d+\$)?(@|l?d)/g) || [];
  return m.map(x => x.replace(/\d+\$/, '')).sort().join(',');
}
function run(argv) {
  const d = $.NSDictionary.dictionaryWithContentsOfFile(argv[0]);
  if (d.isNil()) throw new Error('cannot read ' + argv[0]);
  const obj = ObjC.deepUnwrap(d);
  const out = [];
  for (const k of Object.keys(obj).sort()) {
    const v = obj[k];
    if (typeof v === 'string') { out.push(k + '\t' + sig(v)); continue; }
    // stringsdict entry: collect placeholders from every plural form
    const forms = new Set(); let hasOther = true;
    for (const [name, spec] of Object.entries(v)) {
      if (name === 'NSStringLocalizedFormatKey' || typeof spec !== 'object') continue;
      if (!('other' in spec)) hasOther = false;
      for (const [cat, s] of Object.entries(spec))
        if (!cat.startsWith('NSString')) forms.add(sig(s));
    }
    out.push(k + '\t' + (hasOther ? '' : 'NO_OTHER_FORM;') + [...forms].sort().join('|'));
  }
  return out.join('\n');
}
JS
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

echo "==> plutil -lint"
for lang in "${LANGS[@]}"; do
  [[ -d "Resources/$lang.lproj" ]] || { err "missing Resources/$lang.lproj"; continue; }
  for t in "${TABLES[@]}"; do
    f="Resources/$lang.lproj/$t"
    [[ -f "$f" ]] || { err "missing $f"; continue; }
    plutil -lint -s "$f" || err "$f does not lint"
  done
done
extra=$(ls -d Resources/*.lproj | sed 's#Resources/##; s#\.lproj##' | grep -vxF -f <(printf '%s\n' "${LANGS[@]}") || true)
[[ -z "$extra" ]] || err "unexpected localizations: $extra"
(( fail == 0 )) || exit 1

echo "==> keys and placeholders vs. $BASE"
for t in "${TABLES[@]}"; do dump "Resources/$BASE.lproj/$t" > "$tmp/$BASE.$t"; done
for lang in "${LANGS[@]}"; do
  [[ "$lang" == "$BASE" ]] && continue
  for t in "${TABLES[@]}"; do
    dump "Resources/$lang.lproj/$t" > "$tmp/$lang.$t"
    missing=$(comm -23 <(cut -f1 "$tmp/$BASE.$t") <(cut -f1 "$tmp/$lang.$t"))
    surplus=$(comm -13 <(cut -f1 "$tmp/$BASE.$t") <(cut -f1 "$tmp/$lang.$t"))
    [[ -z "$missing" ]] || err "$lang/$t is missing: $(echo $missing)"
    [[ -z "$surplus" ]] || err "$lang/$t has extra keys: $(echo $surplus)"
    if [[ "$t" == *.strings ]]; then
      bad=$(join -t $'\t' "$tmp/$BASE.$t" "$tmp/$lang.$t" | awk -F'\t' '$2 != $3 { print $1 }')
    else
      # plural forms may drop the number (e.g. "one" in some languages) but never add one
      bad=$(join -t $'\t' "$tmp/$BASE.$t" "$tmp/$lang.$t" | awk -F'\t' '$3 ~ /NO_OTHER_FORM/ { print $1 }')
    fi
    [[ -z "$bad" ]] || err "$lang/$t placeholder mismatch: $(echo $bad)"
  done
done
grep -q NO_OTHER_FORM "$tmp/$BASE.Localizable.stringsdict" && err "$BASE stringsdict lacks an 'other' form"

echo "==> keys used in Sources/"
cat "$tmp/$BASE".* | cut -f1 | sort -u > "$tmp/known"
grep -ohE 'L10n\.tr\("[^"]+"' Sources/*.swift | sed -E 's/L10n\.tr\("//; s/"$//' | sort -u > "$tmp/used"
undefined=$(comm -13 "$tmp/known" "$tmp/used")
[[ -z "$undefined" ]] || err "used in Sources but not defined: $(echo $undefined)"
while read -r key; do
  grep -qF "\"$key\"" Sources/*.swift || err "defined but never used: $key"
done < "$tmp/known"

if (( fail )); then echo "==> FAILED"; exit 1; fi
echo "==> OK: ${#LANGS[@]} languages, $(wc -l < "$tmp/known" | tr -d ' ') keys"
