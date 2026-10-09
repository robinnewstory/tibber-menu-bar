// Builds App/Resources/Localizable.xcstrings from the keys xcodebuild extracted (en.xliff) and the translation tables.
// Usage: node make-catalog.js <en.xliff> <out.xcstrings> <translations.js>...
const fs = require('fs');
const [,, xliffPath, outPath, ...tablePaths] = process.argv;
const tables = tablePaths.map(p => require(require('path').resolve(p)));
const untranslated = new Set(tables.flatMap(t => t.untranslated || []));
const merged = {};
for (const t of tables) for (const [k, v] of Object.entries(t)) { if (k === 'untranslated') continue; merged[k] = { ...(merged[k] || {}), ...v }; }
const x = fs.readFileSync(xliffPath, 'utf8');
const unesc = s => s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'");
const file = x.match(/<file original="App\/Resources\/Localizable.xcstrings"[\s\S]*?<\/file>/)[0];
// The trans-unit id is the key the app looks up at runtime ("· next %@ %@"); the <source> is the English value,
// which Xcode writes with positional specifiers ("%1$@ %2$@"). A plural variation's id is "key|==|plural.one".
const keys = [...new Set([...file.matchAll(/<trans-unit id="([^"]*)"/g)].map(m => unesc(m[1]).split('|==|')[0]))];
// Translation tables may spell keys positionally; match them on the runtime form.
const runtimeForm = k => k.replace(/%(\d+)\$/g, '%');
const byRuntimeKey = Object.fromEntries(Object.entries(merged).map(([k, v]) => [runtimeForm(k), v]));
const langs = [...new Set(Object.values(merged).flatMap(v => Object.keys(v)))].filter(l => l !== 'en').sort();
const placeholders = s => (runtimeForm(s).match(/%(lld|@|d|f|s)/g) || []).sort().join(',');
const problems = [];
const strings = {};
const unit = v => ({ stringUnit: { state: 'translated', value: v } });
const wrap = v => typeof v === 'string' ? unit(v) : { variations: { plural: { one: unit(v.one), other: unit(v.other) } } };
for (const key of keys.sort()) {
  if (untranslated.has(key)) { strings[key] = { shouldTranslate: false }; continue; }
  const tr = byRuntimeKey[key];
  if (!tr) { problems.push('no translation: ' + key); continue; }
  const localizations = {};
  if (tr.en) localizations.en = wrap(tr.en);
  for (const l of langs) {
    if (tr[l] == null) { problems.push(`missing ${l}: ${key}`); continue; }
    for (const v of (typeof tr[l] === 'string' ? [tr[l]] : [tr[l].one, tr[l].other]))
      if (placeholders(v) !== placeholders(key)) problems.push(`placeholder mismatch ${l}: ${key} -> ${v}`);
    localizations[l] = wrap(tr[l]);
  }
  strings[key] = { localizations };
}
for (const k of Object.keys(byRuntimeKey)) if (!keys.includes(k)) problems.push('translation for unknown key: ' + k);
if (problems.length) { console.error(problems.join('\n')); process.exit(1); }
fs.writeFileSync(outPath, JSON.stringify({ sourceLanguage: 'en', strings, version: '1.0' }, null, 2) + '\n');
console.log(`catalog: ${keys.length} keys, languages: ${langs.join(' ')}`);
