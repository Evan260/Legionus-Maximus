extends Node
## The language the game shows: loads every translated column of strings.csv, picks the saved or system language and
## tells the game when it changes. It is an autoload named Lang.

signal changed

## Each language in its own words, so a player can find theirs whatever is showing. The order is the order of the picker.
const NATIVE_NAMES := {"en": "English", "fr": "Français", "de": "Deutsch", "es": "Español", "it": "Italiano", "pt_BR": "Português (BR)",
	"pl": "Polski", "tr": "Türkçe", "ru": "Русский", "uk": "Українська", "ja": "日本語", "ko": "한국어", "zh_CN": "简体中文", "zh_TW": "繁體中文"}
## Languages Silkscreen has every letter for; the rest are drawn in Fusion Pixel's 10 px Latin font.
const SILKSCREEN := ["en", "fr", "de", "es", "it", "pt"]
## Languages drawn in Fusion Pixel's 8 px Chinese, Japanese and Korean fonts.
const HAN := {"ja": "ja", "ko": "ko", "zh_CN": "zh_hans", "zh_TW": "zh_tw"}
const FONTS := "res://assets/fonts/"

var code := "en"
var _fonts := {}


func _ready() -> void:
	for file in ResourceLoader.list_directory("res://translations/"):
		if file.get_extension() == "translation":
			var t: Translation = load("res://translations/" + file)
			if t.locale == "en" or t.get_message("Language") != "":
				TranslationServer.add_translation(t)
	var want := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			want = a.trim_prefix("--lang=")
		elif a == "--run-tests" or a == "--bench":
			want = "en"
	if want == "":
		want = str(Profile.setting("language"))
	apply(want, false)


## Shows the game in a language ("" for the computer's own, English when it is not translated) and tells the screens.
func apply(language: String, announce := true) -> void:
	var have := TranslationServer.get_loaded_locales()
	code = language if language in have else _system_language()
	TranslationServer.set_locale(code)
	if announce:
		changed.emit()


## The computer's own language if the game has it, matching "fr_CA" to "fr" and "zh_Hans_CN" to "zh_CN"; otherwise English.
func _system_language() -> String:
	var have := TranslationServer.get_loaded_locales()
	var os := OS.get_locale()
	if os in have:
		return os
	if os.begins_with("zh"):
		var traditional := os.contains("Hant") or os.ends_with("TW") or os.ends_with("HK") or os.ends_with("MO")
		var zh := "zh_TW" if traditional else "zh_CN"
		return zh if zh in have else "en"
	var lang := OS.get_locale_language()
	for loc in have:
		if loc.get_slice("_", 0) == lang:
			return loc
	return "en"


func languages() -> Array:
	var have := TranslationServer.get_loaded_locales()
	return NATIVE_NAMES.keys().filter(func(loc: String) -> bool: return loc in have)


func is_han() -> bool:
	return HAN.has(code)


## True for languages whose letters Silkscreen has.
func uses_silkscreen(loc := "") -> bool:
	return (loc if loc != "" else code).get_slice("_", 0) in SILKSCREEN


## The text font of the language (the one showing by default): Silkscreen where it has the letters, Fusion Pixel otherwise, never smoothed.
func font(loc := "") -> Font:
	var l := loc if loc != "" else code
	if not _fonts.has(l):
		var ten := _crisp(load(FONTS + "fusion-pixel-10px-proportional-latin.ttf.woff2"))
		if HAN.has(l):
			var han := _crisp(load(FONTS + "fusion-pixel-8px-proportional-%s.ttf.woff2" % HAN[l]))
			han.fallbacks = [ten]
			_fonts[l] = han
		elif uses_silkscreen(l):
			var silk := _crisp(load(FONTS + "Silkscreen-Regular.ttf"))
			silk.fallbacks = [ten]
			_fonts[l] = silk
		else:
			_fonts[l] = ten
	return _fonts[l]


## The size the font is drawn for at text size 1; text size 2 doubles it.
func base_px(loc := "") -> int:
	var l := loc if loc != "" else code
	return 8 if (uses_silkscreen(l) or HAN.has(l)) else 10


func _crisp(source: FontFile) -> FontFile:
	var f: FontFile = source.duplicate()
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f
