import QtQuick
import Quickshell
import Quickshell.Io
import "Language.js" as Language

// The plugin's string catalogs (i18n/<code>.json). Unlike Commons.Translations,
// which follows only the Omarchy language, this falls back to the system
// locale when no Omarchy language is set (see Language.js). English is the
// default and the per-string fallback. The Omarchy language file is watched,
// so switching language under Setup re-renders without a restart.
QtObject {
  id: root

  // A filesystem path or file:// URL (Qt.resolvedUrl("i18n") from the plugin).
  property var directory: ""

  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  readonly property string language: Language.resolve(
    omarchyLanguageFile.text(),
    Quickshell.env("LC_ALL"),
    Quickshell.env("LC_MESSAGES"),
    Quickshell.env("LANG"))
  readonly property string baseLanguage: Language.base(language)
  readonly property string directoryPath: decodeURIComponent(String(directory).replace(/^file:\/\//, "")).replace(/\/+$/, "")

  readonly property var englishStrings: parseCatalog(englishFile.text())
  readonly property var baseStrings: baseLanguage === "en" ? ({}) : parseCatalog(baseFile.text())
  readonly property var languageStrings: language === baseLanguage ? ({}) : parseCatalog(languageFile.text())

  function lookup(key) {
    var layers = [languageStrings, baseStrings, englishStrings]
    for (var i = 0; i < layers.length; i++) {
      var value = layers[i][key]
      if (value !== undefined && value !== null) return { value: value, layer: i }
    }
    return null
  }

  function t(key, fallback) {
    var found = lookup(key)
    var value = found ? found.value : undefined
    if (value && typeof value === "object") value = value.other
    if (typeof value === "string" && value.length > 0) return value
    return fallback !== undefined ? fallback : key
  }

  function tn(key, count, fallback) {
    var found = lookup(key)
    if (!found) return fallback !== undefined ? fallback : key
    var value = found.value
    if (typeof value === "string") return value
    // Use the plural rules of the language whose catalog supplied the entry.
    var code = found.layer === 2 ? "en" : language
    var form = value[Language.pluralCategory(code, count)]
    if (typeof form !== "string" || form.length === 0) form = value.other
    return typeof form === "string" ? form : (fallback !== undefined ? fallback : key)
  }

  function parseCatalog(raw) {
    try {
      var parsed = JSON.parse(raw || "{}")
      return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({})
    } catch (e) {
      return ({})
    }
  }

  property FileView omarchyLanguageFile: FileView {
    // Same override as Omarchy, so tests can pin a language.
    path: Quickshell.env("OMARCHY_LANGUAGE_FILE") || (root.configHome + "/omarchy/language")
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  property FileView englishFile: FileView {
    path: root.directoryPath + "/en.json"
    printErrors: false
    blockLoading: true
  }

  property FileView baseFile: FileView {
    path: root.directoryPath + "/" + root.baseLanguage + ".json"
    printErrors: false
    blockLoading: true
  }

  property FileView languageFile: FileView {
    path: root.directoryPath + "/" + root.language + ".json"
    printErrors: false
    blockLoading: true
  }
}
