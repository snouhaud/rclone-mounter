.pragma library

// Picks the plugin's display language:
//   1. the language chosen in Omarchy (~/.config/omarchy/language), when set;
//   2. otherwise the system locale (LC_ALL, then LC_MESSAGES, then LANG);
//   3. English when neither names a language.
// The caller then falls back to the base language and to English per string,
// so a language without a catalog simply shows English.

function normalize(code) {
  var value = String(code || "").trim()
  // Locale forms: fr_FR.UTF-8, fr_FR@euro, pt_BR -> fr-FR, pt-BR.
  value = value.split(".")[0].split("@")[0].replace("_", "-")
  if (value === "C" || value === "POSIX") return ""
  var match = /^([a-zA-Z]{2,3})(?:-([a-zA-Z]{2}))?$/.exec(value)
  if (!match) return ""
  return match[1].toLowerCase() + (match[2] ? "-" + match[2].toUpperCase() : "")
}

function resolve(omarchyLanguage, lcAll, lcMessages, lang) {
  var explicit = normalize(omarchyLanguage)
  if (explicit !== "") return explicit
  var candidates = [lcAll, lcMessages, lang]
  for (var i = 0; i < candidates.length; i++) {
    var code = normalize(candidates[i])
    if (code !== "") return code
  }
  return "en"
}

function base(code) {
  return String(code || "en").split("-")[0]
}

// CLDR plural category for the languages this plugin ships (en, fr); any
// other language uses English rules, matching its English fallback strings.
function pluralCategory(code, count) {
  var n = Math.abs(Number(count))
  if (base(code) === "fr") return (n === 0 || n === 1) ? "one" : "other"
  return n === 1 ? "one" : "other"
}
