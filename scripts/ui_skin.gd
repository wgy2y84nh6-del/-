extends RefCounted
## Presentation only. Supplied PNG bytes and their aspect ratios are retained.

const ROOT := "res://assets/ui/"
const FILL := Color("302037")
const EDGE := Color("b786b4")
const INK := Color("ffced4")
const FrameClass = preload("res://scripts/ui_frame.gd")
const FILES := {
	"joy_full": "Заполнение_Радости_Полная.png", "joy_empty": "Заполнение_Радости_Пустая.png",
	"energy_full": "Заполнение_Энергия_Полная.png", "energy_empty": "Заполнение_Энергия_Пустая.png",
	"hunger_full": "Заполнение_сытости_Полная.png", "hunger_empty": "Заполнение_сытости_Пустая.png",
	"restart": "Иллюстрация_без_названия 1.png", "food_hint": "Иллюстрация_без_названия 2.png",
	"exit": "Кнопка_«Выход».png", "pet": "Кнопка_«Гладить».png", "play": "Кнопка_«Играть».png",
	"visit": "Кнопка_«К_питомцу».png", "gut": "Кнопка_«Кишки».png", "feed": "Кнопка_«Кормить».png",
	"family1": "Кнопка_«Лилу».png", "settings": "Кнопка_«Настройки».png", "family0": "Кнопка_«Пух».png",
	"family2": "Кнопка_«Ростик».png", "heart": "Кнопка_«Сердце».png", "sleep": "Кнопка_«Спать».png",
	"human": "Кнопка_«Человек».png", "audio": "Кнопка_Звука.png",
	"volume_sound": "Кнопка_Настройка_«Звук».png", "volume_music": "Кнопка_Настройка_«Музыка».png",
	"continue": "Кнопка_Пуска.png", "pause": "Кнопка_паузы.png",
	"logo": "Логотип_«Ты_мой_дом».png", "menu_logo": "Логотип_Ты_Мой_Дом_Из_Меню.png",
	"card1": "Основная_рамка_с_паразитом_Лилу.png", "card0": "Основная_рамка_с_паразитом_Пух.png",
	"card2": "Основная_рамка_с_паразитом_Ростик.png", "family": "Панель_«Твоя_семья».png",
	"human1_full": "Полоска_состояния_человека_1_Стадия_Заполненная.png",
	"human1_empty": "Полоска_состояния_человека_1_Стадия_НеЗаполненная.png",
	"human2_full": "Полоска_состояния_человека_2_Стадия_Заполненная.png",
	"human2_empty": "Полоска_состояния_человека_2_Стадия_НеЗаполненная.png",
	"human3_full": "Полоска_состояния_человека_3_Стадия_Заполненная.png",
	"human3_empty": "Полоска_состояния_человека_3_Стадия_Не_Заполненная.png",
	"world_frame": "Рамка_игрового_поля.png", "care": "Рамка_панели_«ЗАБОТА».png",
	"view_heart": "Табличка_«СЕРДЦЕ».png", "background": "Фон_Игрового_Поля.png",
	"header": "Фон_верхней_панели.png"
}

var textures: Dictionary = {}
var regions: Dictionary = {}
var atlases: Dictionary = {}
var font: FontVariation
var heading: FontVariation
var frame_regions: Dictionary = {}

func _init() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "catalog.json"))
	frame_regions = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "frame_regions.json"))
	for key in FILES:
		textures[key] = load(ROOT + FILES[key])
		var r: Array = catalog[FILES[key]].region
		regions[key] = Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1])
	var base: FontFile = load("res://assets/fonts/Tiny5.ttf")
	base.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	base.oversampling = 1.0
	font = FontVariation.new()
	font.base_font = base
	font.variation_opentype = {"wght": 400.0}
	font.fallbacks = [load("res://assets/fonts/DejaVuSans.ttf")]
	heading = FontVariation.new()
	heading.base_font = base
	heading.variation_opentype = {"wght": 700.0}
	heading.fallbacks = [load("res://assets/fonts/DejaVuSans.ttf")]

func tex(key: String) -> Texture2D:
	return textures[key]

func region(key: String) -> Rect2:
	return regions[key]

func atlas(key: String) -> AtlasTexture:
	if not atlases.has(key):
		var cropped := AtlasTexture.new()
		cropped.atlas = textures[key]
		cropped.region = regions[key]
		atlases[key] = cropped
	return atlases[key]

func image(parent: Control, key: String, rect: Rect2) -> TextureRect:
	var node := TextureRect.new()
	node.name = "Art_" + key
	node.texture = atlas(key)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	# Fit, never stretch: only transparent outer canvas is omitted.
	var factor := minf(rect.size.x / region(key).size.x, rect.size.y / region(key).size.y)
	node.size = region(key).size * factor
	node.position = rect.position + (rect.size - node.size) / 2.0
	parent.add_child(node)
	return node

func frame(fill := FILL, border := EDGE, radius := 12.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(int(radius))
	box.corner_detail = 1
	box.anti_aliasing = false
	box.content_margin_left = 10
	box.content_margin_right = 10
	return box

func panel(parent: Control, key: String, rect: Rect2, title := false, title_size := 2.0, title_position := Vector2(24, 10), centered := false) -> Control:
	var node = FrameClass.new()
	node.configure(self, key)
	node.position = rect.position
	node.size = rect.size
	node.show_title = title
	node.title_scale = title_size
	node.title_offset = title_position
	node.center_title = centered
	parent.add_child(node)
	return node

func apply_button(button: Button, asset: String) -> void:
	if button.has_meta("art_skin") and button.get_meta("art_skin") == asset:
		return
	button.set_meta("art_skin", asset)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_font_override("font", heading)
	if not asset.is_empty():
		var box := StyleBoxTexture.new()
		box.texture = atlas(asset)
		for state in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state, box)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
			button.add_theme_color_override(state, Color.TRANSPARENT)
	else:
		var fill := Color("503650") if button.size.x / button.size.y < 2.0 else FILL
		var scale_factor := button.size.y / 80.0
		var border_width := maxi(1, roundi(2.0 * scale_factor))
		var normal := frame(fill, EDGE, 16.0 * scale_factor)
		normal.set_border_width_all(border_width)
		var hover := frame(fill, INK, 16.0 * scale_factor)
		hover.set_border_width_all(border_width)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.add_theme_stylebox_override("disabled", normal)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, INK)
		button.add_theme_color_override("font_disabled_color", EDGE)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if not button.has_node("StateOutline"):
		var accent := StateOutline.new()
		accent.name = "StateOutline"
		accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(accent)
		for signal_name in ["mouse_entered", "mouse_exited", "focus_entered", "focus_exited"]:
			button.connect(signal_name, accent.queue_redraw)

func mark(button: Button, selected: bool) -> void:
	if button.get_meta("selected_art", false) != selected:
		button.set_meta("selected_art", selected)
		button.get_node("StateOutline").queue_redraw()

func fit_button(button: Button) -> void:
	if button.get_meta("art_skin", "") != "":
		return
	if button.get_meta("fitted_text", "\u0001") == button.text:
		return
	var font_size: int = button.get_meta("label_size", 28)
	var lines := button.text.split("\n")
	while font_size > 14:
		var width := 0.0
		for line in lines:
			width = maxf(width, heading.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		if width <= button.size.x - 24 and heading.get_height(font_size) * lines.size() <= button.size.y - 12:
			break
		font_size -= 1
	button.add_theme_font_size_override("font_size", font_size)
	button.set_meta("fitted_text", button.text)

func fit_label(label: Label, preferred := 22) -> void:
	var target: Vector2 = label.get_meta("text_box", label.size)
	var cache_key := label.text + ":" + str(target)
	if label.get_meta("fitted_label", "") == cache_key:
		return
	var font_size := preferred
	var face: Font = label.get_theme_font("font")
	while font_size > 16 and face.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > target.x:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)
	label.size = target
	label.set_meta("fitted_label", cache_key)

class StateOutline extends Control:
	func _draw() -> void:
		var owner_button: Button = get_parent()
		if owner_button.disabled:
			return
		if not owner_button.is_hovered() and not owner_button.has_focus() and not owner_button.get_meta("selected_art", false):
			return
		var s := owner_button.size
		var cut := minf(12.0, s.y / 5.0)
		var p := PackedVector2Array([Vector2(cut, 2), Vector2(s.x - cut, 2), Vector2(s.x - 2, cut),
			Vector2(s.x - 2, s.y - cut), Vector2(s.x - cut, s.y - 2), Vector2(cut, s.y - 2),
			Vector2(2, s.y - cut), Vector2(2, cut), Vector2(cut, 2)])
		draw_polyline(p, INK, 2.0, false)
