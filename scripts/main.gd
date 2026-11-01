extends Control

const BACK := Color("25182f")
const PANEL := Color("302038")
const PINK := Color("c780ab")
const INK := Color("ffe0cd")
const MUTED := Color("c9a2bc")
const ORGAN_NAMES := {"heart": "СЕРДЦЕ", "brain": "МОЗГ", "gut": "КИШЕЧНИК", "human": "ЧЕЛОВЕК"}
const SAVE_PATH := "user://home_save.json"
const WEB_SAVE_KEY := "you-are-my-home:save:v1"
const StateClass = preload("res://scripts/game_state.gd")
const ArtClass = preload("res://scripts/art.gd")
const WorldClass = preload("res://scripts/world.gd")
const AudioClass = preload("res://scripts/audio.gd")

var state: ParasiteGame
var art: HomeArt
var audio: HomeAudio
var page: Control
var content: Control
var overlay: Control
var world: HomeWorld
var body_font: Font = preload("res://assets/fonts/DejaVuSans.ttf")
var title_font: Font = preload("res://assets/fonts/DejaVuSerif-Bold.ttf")
var mode := "menu"
var clock := 0.0
var save_clock := 0.0
var bridge_clock := 0.0
var browser_started := false
var pending_resume := false
var labels: Dictionary = {}
var bars: Dictionary = {}
var buttons: Dictionary = {}
var family: Array[Button] = []
var portrait: TextureRect
var latest_result := ""

func _ready() -> void:
	state = StateClass.new()
	state.event.connect(_on_event)
	art = ArtClass.new()
	audio = AudioClass.new()
	add_child(audio)
	page = Control.new()
	page.size = Vector2(1600, 900)
	page.draw.connect(_paint)
	add_child(page)
	get_viewport().size_changed.connect(_fit)
	_fit()
	build_menu()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__homeReady = true;", true)

func _fit() -> void:
	if not page:
		return
	var area := get_viewport_rect().size
	var factor := minf(area.x / 1600.0, area.y / 900.0)
	page.scale = Vector2.ONE * factor
	page.position = (area - Vector2(1600, 900) * factor) / 2.0

func _process(dt: float) -> void:
	clock += dt
	if mode == "game":
		state.tick(dt)
		audio.set_stage(state.live_count())
		refresh()
		if latest_result != state.result and not state.result.is_empty():
			latest_result = state.result
			save_game()
			show_ending()
		save_clock += dt
		if save_clock >= 2.0:
			save_clock = 0.0
			save_game()
	bridge_clock += dt
	if OS.has_feature("web") and bridge_clock >= 0.1:
		bridge_clock = 0.0
		var observation := state.export_state()
		observation["mode"] = mode
		observation["paused"] = state.paused
		observation["petting"] = state.petting
		observation["hearts"] = 3 if state.petting and mode == "game" else 0
		observation["overlay"] = is_instance_valid(overlay)
		observation["music_stage"] = audio.stage
		observation["music_playing"] = audio.music.playing
		observation["music_volume"] = audio.music_volume
		observation["effects_volume"] = audio.effects_volume
		var placements: Array = []
		for p in state.pets:
			if not p.alive:
				continue
			var a := art.anchor(p)
			placements.append({"id": p.id, "organ": p.organ, "x": a.x, "y": a.y, "frame": art.frame(p)})
		observation["placements"] = placements
		# Read-only observation for regression tests; no commands or time overrides.
		JavaScriptBridge.eval("window.__homeState = " + JSON.stringify(observation) + ";", true)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		stop_petting()
	if event is InputEventScreenTouch and not event.pressed:
		stop_petting()
	if event is InputEventMouseMotion and state.petting:
		# Releasing outside the original control is caught globally above.
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			stop_petting()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if is_instance_valid(overlay):
				close_overlay()
			elif mode == "game":
				toggle_pause()
		if mode == "game" and not is_instance_valid(overlay):
			match event.keycode:
				KEY_1: state.feed()
				KEY_4: state.sleep_toggle()
				KEY_SPACE: toggle_pause()
				KEY_H: navigate("human")
				KEY_Q: navigate("heart")
				KEY_W: navigate("brain")
				KEY_E: navigate("gut")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_MOUSE_EXIT:
		stop_petting()
		if mode == "game":
			save_game()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()

func stop_petting() -> void:
	if state:
		state.petting = false
	if is_instance_valid(world):
		world.queue_redraw()

func _on_event(kind: String) -> void:
	audio.effect("loss" if kind == "death" else kind)
	if kind in ["egg", "hatch", "move", "win", "loss", "death"]:
		save_game()
	if kind == "hatch":
		refresh()

func _polygon(rect: Rect2, cut: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y),
		Vector2(e.x - cut, p.y + cut * 0.4), Vector2(e.x, p.y + cut),
		Vector2(e.x, e.y - cut), Vector2(e.x - cut * 0.4, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y),
		Vector2(p.x + cut, e.y - cut * 0.4), Vector2(p.x, e.y - cut),
		Vector2(p.x, p.y + cut), Vector2(p.x + cut * 0.4, p.y + cut)])

func panel(rect: Rect2, color := PANEL, border := PINK, cut := 12.0) -> void:
	var shape := _polygon(rect, cut)
	page.draw_colored_polygon(shape, color)
	shape.append(shape[0])
	page.draw_polyline(shape, border, 2.0, false)
	var inset := _polygon(rect.grow(-4), maxf(2, cut - 2))
	inset.append(inset[0])
	page.draw_polyline(inset, Color(border, 0.16), 1, false)

func _paint() -> void:
	page.draw_rect(Rect2(0, 0, 1600, 900), BACK)
	# Restrained pixel dithering, using the reference palette only.
	for y in range(8, 900, 8):
		for x in range(8, 1600, 8):
			if (x * 13 + y * 7) % 104 == 0:
				page.draw_rect(Rect2(x, y, 2, 2), Color(0.65, 0.37, 0.54, 0.035))
	if mode == "game":
		panel(Rect2(16, 8, 1568, 82))
		panel(Rect2(16, 110, 360, 470))
		panel(Rect2(16, 590, 360, 178))
		panel(Rect2(400, 110, 820, 70), Color("352138"), Color("e995bb"))
		panel(Rect2(400, 194, 820, 574), Color("211629"), Color("68445f"))
		panel(Rect2(1240, 110, 344, 658))
		panel(Rect2(16, 786, 1568, 98))
		page.draw_line(Vector2(1272, 492), Vector2(1550, 492), PINK, 2)
	else:
		panel(Rect2(14, 12, 1572, 876), Color("291a31"))
		panel(Rect2(456, 70, 688, 116), Color("342038"), Color("d38bb6"), 26)
		page.draw_line(Vector2(92, 129), Vector2(434, 129), PINK, 2)
		page.draw_line(Vector2(1166, 129), Vector2(1508, 129), PINK, 2)
		page.draw_line(Vector2(92, 821), Vector2(1508, 821), PINK, 2)

func clear_content() -> void:
	close_overlay(false)
	if is_instance_valid(content):
		remove_child_from_page(content)
	labels.clear()
	bars.clear()
	buttons.clear()
	family.clear()
	world = null
	content = Control.new()
	content.size = Vector2(1600, 900)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(content)
	page.queue_redraw()

func remove_child_from_page(node: Node) -> void:
	page.remove_child(node)
	node.queue_free()

func text_node(text: String, rect: Rect2, font_size := 22, center := true, heading := false, parent: Control = null) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", title_font if heading else body_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else content).add_child(label)
	return label

func style(fill: Color, line: Color, primary := false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = line
	box.set_border_width_all(2)
	box.set_corner_radius_all(11)
	box.corner_detail = 2
	box.content_margin_left = 8
	box.content_margin_right = 8
	if primary:
		box.shadow_color = Color(1, 0.28, 0.56, 0.22)
		box.shadow_size = 10
	return box

func bar_style(fill: Color, line: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = line
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.corner_detail = 1
	return box

func button(key: String, title: String, rect: Rect2, action: Callable, primary := false, parent: Control = null, font_size := 24) -> Button:
	var b := Button.new()
	b.name = key
	b.position = rect.position
	b.size = rect.size
	b.text = title
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_override("font", body_font)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color("fff0e2"))
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", Color("90748c"))
	b.add_theme_stylebox_override("normal", style(Color("8d4a72") if primary else Color("543650"), Color("ffd5e0") if primary else PINK, primary))
	b.add_theme_stylebox_override("hover", style(Color("995578"), Color("ffcade"), true))
	b.add_theme_stylebox_override("pressed", style(Color("ae587f"), Color("ffe0de")))
	b.add_theme_stylebox_override("disabled", style(Color("36263c"), Color("72516b")))
	b.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), Color("fff1ce")))
	b.pressed.connect(func():
		audio.unlock()
		audio.effect("click")
		action.call())
	(parent if parent else content).add_child(b)
	buttons[key] = b
	return b

func build_menu() -> void:
	mode = "menu"
	state.paused = true
	clear_content()
	text_node("Ты мой дом", Rect2(456, 66, 688, 116), 63, true, true)
	button("play", "Играть", Rect2(510, 250, 580, 86), start_or_resume, true, null, 40)
	button("settings", "Настройки", Rect2(510, 391, 580, 84), show_settings, false, null, 38)
	button("music", "Музыка", Rect2(510, 532, 580, 84), show_settings, false, null, 38)
	button("exit", "Выход", Rect2(510, 674, 580, 84), show_exit, false, null, 38)
	text_node("ПАРАЗИТ-ТАМАГОЧИ", Rect2(510, 837, 580, 24), 13).modulate = MUTED

func start_or_resume() -> void:
	var saved_text := read_saved_text()
	if not saved_text.is_empty():
		var parsed = JSON.parse_string(saved_text)
		if parsed is Dictionary:
			if not state.import_state(parsed):
				state.notice = "Сохранение повреждено. Начинаем новый дом."
	state.paused = false
	latest_result = ""
	build_game()
	if not state.result.is_empty():
		latest_result = state.result
		show_ending()

func build_game() -> void:
	mode = "game"
	clear_content()
	text_node("Ты мой дом", Rect2(36, 12, 365, 65), 37, true, true)
	labels["view"] = text_node("СЕРДЦЕ", Rect2(410, 14, 330, 62), 31, true, true)
	button("pause", "Ⅱ", Rect2(818, 24, 82, 46), toggle_pause, false, null, 26)
	button("help", "?", Rect2(994, 24, 58, 46), show_help, false, null, 26)
	button("audio", "♪", Rect2(1071, 24, 58, 46), show_settings, false, null, 27)
	labels["human"] = text_node("ЧЕЛОВЕК · СТАДИЯ 1", Rect2(1185, 13, 370, 30), 18)
	var human_bar := ProgressBar.new()
	human_bar.position = Vector2(1188, 53)
	human_bar.size = Vector2(370, 20)
	human_bar.show_percentage = false
	human_bar.add_theme_font_size_override("font_size", 8)
	human_bar.add_theme_stylebox_override("background", bar_style(Color("56334c"), PINK))
	human_bar.add_theme_stylebox_override("fill", bar_style(Color("f98eaf"), Color("ffc7d6")))
	content.add_child(human_bar)
	human_bar.size = Vector2(370, 20)
	bars["human"] = human_bar
	labels["name"] = text_node("Пух", Rect2(42, 117, 302, 48), 34, false, true)
	portrait = TextureRect.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	content.add_child(portrait)
	labels["home"] = text_node("Дома в сердце", Rect2(55, 309, 280, 26), 15)
	var stat_names := ["Сытость", "Энергия", "Довольство", "Здоровье"]
	var stat_keys := ["hunger", "energy", "joy", "health"]
	var colors := ["f6a0af", "bdace7", "ffd17e", "ff87ab"]
	for i in range(4):
		var y := 340 + i * 43
		text_node(stat_names[i], Rect2(69, y, 206, 23), 18, false)
		labels[stat_keys[i]] = text_node("85%", Rect2(294, y, 60, 23), 18)
		var bar := ProgressBar.new()
		bar.position = Vector2(70, y + 25)
		bar.size = Vector2(207, 16)
		bar.show_percentage = false
		bar.add_theme_font_size_override("font_size", 8)
		bar.add_theme_stylebox_override("background", bar_style(Color("67415e"), Color("bc7da1")))
		bar.add_theme_stylebox_override("fill", bar_style(Color(colors[i]), Color(colors[i]).lightened(0.15)))
		content.add_child(bar)
		bar.size = Vector2(207, 16)
		bars[stat_keys[i]] = bar
	text_node("Твоя семья", Rect2(42, 596, 307, 32), 24)
	for i in range(3):
		var index := i
		var b := button("family%d" % i, ["Пух", "Лилу", "Ростик"][i], Rect2(39 + i * 108, 638, 99, 44), func(): state.select_pet(index), false, null, 17)
		family.append(b)
	button("visit", "К питомцу →", Rect2(40, 700, 312, 49), func(): navigate(state.pets[state.selected].organ), false, null, 25)
	labels["notice"] = text_node(state.notice, Rect2(417, 116, 786, 56), 19)
	labels["notice"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	world = WorldClass.new()
	world.state = state
	world.art = art
	world.position = Vector2(410, 225)
	world.size = Vector2(800, 450)
	world.clip_contents = true
	world.food_pressed.connect(func(organ: String): state.collect(organ))
	world.pet_pressed.connect(func(index: int):
		state.select_pet(index)
		state.start_petting())
	world.pet_released.connect(stop_petting)
	content.add_child(world)
	labels["caption"] = text_node("", Rect2(415, 683, 790, 30), 18)
	labels["timers"] = text_node("", Rect2(416, 725, 788, 27), 17)
	text_node("ЗАБОТА", Rect2(1260, 122, 304, 45), 26, true, true)
	button("feed", "Кормить", Rect2(1264, 190, 296, 62), func(): state.feed(), true, null, 28)
	var pet_button := button("pet", "Гладить", Rect2(1264, 305, 296, 62), func(): pass, false, null, 21)
	pet_button.button_down.connect(func():
		audio.unlock()
		state.start_petting())
	pet_button.button_up.connect(stop_petting)
	pet_button.mouse_exited.connect(stop_petting)
	button("sleep", "Спать", Rect2(1264, 421, 296, 62), func(): state.sleep_toggle(), false, null, 28)
	labels["food"] = text_node("Еда · 6", Rect2(1270, 509, 280, 42), 28, true, true)
	text_node("Одно кормление = 3 еды", Rect2(1267, 554, 290, 30), 16)
	text_node("Собирай по одному шарику\nв мозгу и кишечнике", Rect2(1266, 587, 293, 54), 16)
	button("move", "Переселить", Rect2(1264, 659, 296, 53), func(): state.relocate(), false, null, 22)
	labels["count"] = text_node("Паразитов · 1 / 3", Rect2(1264, 722, 296, 30), 18)
	button("human", "Человек", Rect2(34, 805, 255, 61), func(): navigate("human"), false, null, 25)
	button("heart", "Сердце", Rect2(311, 805, 250, 61), func(): navigate("heart"), false, null, 25)
	button("brain", "Мозг", Rect2(582, 805, 250, 61), func(): navigate("brain"), false, null, 25)
	button("gut", "Кишечник", Rect2(853, 805, 250, 61), func(): navigate("gut"), false, null, 25)
	button("menu", "Меню", Rect2(1125, 805, 172, 61), func():
		save_game()
		build_menu(), false, null, 24)
	button("restart", "Заново", Rect2(1318, 805, 248, 61), confirm_restart, false, null, 25)
	refresh()

func refresh() -> void:
	if mode != "game" or labels.is_empty():
		return
	if not state.pets[state.selected].alive:
		state.selected = 0
	var p: Dictionary = state.pets[state.selected]
	labels["name"].text = p.name
	labels["view"].text = ORGAN_NAMES[state.view]
	labels["home"].text = ("Сладко спит · " if p.sleeping else "Дома · ") + ORGAN_NAMES[p.organ].to_lower()
	labels["notice"].text = state.notice
	labels["food"].text = "Еда · %d" % state.food
	labels["count"].text = "Паразитов · %d / 3" % state.live_count()
	labels["human"].text = "ЧЕЛОВЕК · СТАДИЯ %d" % maxi(1, state.live_count())
	bars["human"].value = 100 - (maxi(1, state.live_count()) - 1) * 32
	if state.final_left >= 0:
		bars["human"].value = 36 * state.final_left / 40.0
	for key in ["hunger", "energy", "joy", "health"]:
		bars[key].value = p[key]
		labels[key].text = "%d%%" % ceili(p[key])
	var f := art.frame(p)
	portrait.texture = art.tex(art.pet_file(p, f))
	portrait.position = Vector2(129, 188) + art.frame_offset(p, f) * 1.45
	portrait.size = Vector2(96, 96) * 1.45
	for i in range(3):
		family[i].disabled = i >= state.pets.size() or not state.pets[i].alive
		family[i].modulate = Color.WHITE if i == state.selected else Color("baa2b7")
	buttons["sleep"].text = "Разбудить" if p.sleeping else "Спать"
	buttons["pause"].text = "▶" if state.paused else "Ⅱ"
	buttons["feed"].disabled = state.paused or not state.result.is_empty()
	buttons["pet"].disabled = state.paused or not state.result.is_empty()
	buttons["sleep"].disabled = state.paused or not state.result.is_empty()
	buttons["move"].disabled = state.paused or p.id == 1 or p.organ != "heart" or not state.result.is_empty()
	if p.id > 1 and p.organ == "heart":
		buttons["move"].text = "Переселить → " + ("мозг" if p.id == 2 else "кишечник")
	else:
		buttons["move"].text = "Дома · " + ORGAN_NAMES[p.organ].to_lower()
	for key in ["human", "heart", "brain", "gut"]:
		buttons[key].modulate = Color("ffbad5") if state.view == key else Color.WHITE
	if state.view == "human":
		labels["caption"].text = "Один организм. %d маленьких жильца." % state.live_count()
	elif state.view in ["brain", "gut"]:
		labels["caption"].text = "Нажми на шарик: +1 еда" if state.available_food[state.view] else "Шарик собран · новый через %d с" % ceili(state.food_remaining(state.view))
	else:
		labels["caption"].text = "Пух откладывает яйца только при сытости строго выше 70%."
	var timers := ""
	if state.egg_left >= 0:
		timers += "Вылупление · %d с" % ceili(state.egg_left)
	elif state.live_count() < 3:
		timers += "До яйца · %d с" % ceili(50.0 - state.reproduction_clock)
	else:
		timers += "Семья в сборе"
	if state.final_left >= 0:
		timers += "     |     Финал · %d с" % ceili(state.final_left)
	if state.paused:
		timers = "ПАУЗА  ·  нажми ▶ или пробел"
	labels["timers"].text = timers

func navigate(destination: String) -> void:
	stop_petting()
	state.set_view(destination)
	refresh()

func toggle_pause() -> void:
	stop_petting()
	state.paused = not state.paused
	refresh()
	if state.paused:
		save_game()

func make_overlay(title: String, height := 490.0) -> Control:
	stop_petting()
	if is_instance_valid(overlay):
		close_overlay()
	pending_resume = mode == "game" and not state.paused
	state.paused = true
	overlay = Control.new()
	overlay.size = Vector2(1600, 900)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	page.add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.07, 0.035, 0.09, 0.87)
	shade.size = overlay.size
	overlay.add_child(shade)
	var box := Panel.new()
	box.position = Vector2(410, (900 - height) / 2.0)
	box.size = Vector2(780, height)
	box.add_theme_stylebox_override("panel", style(Color("332039"), PINK, true))
	overlay.add_child(box)
	text_node(title, Rect2(430, box.position.y + 22, 740, 64), 34, true, true, overlay)
	return overlay

func close_overlay(resume := true) -> void:
	if is_instance_valid(overlay):
		remove_child_from_page(overlay)
		overlay = null
		if resume and pending_resume:
			state.paused = false
	pending_resume = false

func show_settings() -> void:
	var ui := make_overlay("Настройки звука")
	text_node("Музыка", Rect2(475, 325, 650, 38), 25, true, false, ui)
	add_slider(Vector2(520, 380), audio.music_volume, func(value: float):
		audio.music_volume = value
		audio.apply_volume()
		audio.save_settings(), ui)
	text_node("Эффекты", Rect2(475, 438, 650, 38), 25, true, false, ui)
	add_slider(Vector2(520, 491), audio.effects_volume, func(value: float):
		audio.effects_volume = value
		audio.apply_volume()
		audio.save_settings(), ui)
	button("audio_back", "Готово", Rect2(600, 595, 400, 62), close_overlay, true, ui, 27)

func add_slider(pos: Vector2, value: float, callback: Callable, parent: Control) -> void:
	var slider := HSlider.new()
	slider.position = pos
	slider.size = Vector2(560, 38)
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.01
	slider.value = value
	slider.add_theme_stylebox_override("slider", style(Color("5d3d59"), PINK))
	slider.add_theme_stylebox_override("grabber_area", style(Color("dc83ac"), Color("ffb8d1")))
	slider.value_changed.connect(callback)
	parent.add_child(slider)

func show_help() -> void:
	var ui := make_overlay("Как обжиться внутри", 650)
	var instructions := "Собирай по одному шарику в мозгу и кишечнике.\nНовый цикл — каждые 7 секунд. Кормление стоит 3 еды.\n\nВыбери питомца слева. Корми, гладь и укладывай спать.\nУдерживай «Гладить» или самого питомца: появятся сердечки.\n\nПух откладывает яйцо раз в 50 секунд при сытости > 70%.\nЯйцо вылупляется за 20 секунд. Пересели Лилу в мозг,\nа Ростика — в кишечник кнопкой «Переселить».\n\nТри живых питомца запускают финал на 40 секунд.\nМладшие голодают быстрее. Пух может вырастить им замену.\n\n1 — кормить   4 — сон   Пробел — пауза\nH — человек   Q / W / E — органы   Esc — закрыть окно\nПрогресс сохраняется автоматически, офлайн-время не считается."
	text_node(instructions, Rect2(435, 230, 730, 390), 19, true, false, ui)
	button("help_back", "Понятно", Rect2(600, 665, 400, 62), close_overlay, true, ui, 27)

func confirm_restart() -> void:
	var ui := make_overlay("Начать заново?", 340)
	text_node("Текущая семья и запас еды будут сброшены.", Rect2(450, 395, 700, 50), 23, true, false, ui)
	button("restart_cancel", "Остаться", Rect2(480, 495, 300, 61), close_overlay, false, ui, 25)
	button("restart_confirm", "Новый дом", Rect2(820, 495, 300, 61), restart_game, true, ui, 25)

func restart_game() -> void:
	close_overlay(false)
	state = StateClass.new()
	state.event.connect(_on_event)
	latest_result = ""
	state.paused = false
	save_game()
	build_game()

func show_ending() -> void:
	var ui := make_overlay("Теперь это ваш дом" if state.result == "win" else "Дом опустел", 360)
	text_node(state.notice, Rect2(460, 390, 680, 85), 22, true, false, ui).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button("ending_look", "Посмотреть", Rect2(480, 505, 300, 61), close_overlay, false, ui, 25)
	button("ending_again", "Начать заново", Rect2(820, 505, 300, 61), restart_game, true, ui, 25)

func show_exit() -> void:
	var ui := make_overlay("До встречи дома", 340)
	text_node("В браузере можно закрыть эту вкладку.\nПрогресс сохранён — семья дождётся тебя.", Rect2(450, 380, 700, 90), 23, true, false, ui)
	button("exit_back", "Остаться", Rect2(600, 505, 400, 61), close_overlay, true, ui, 25)

func save_game() -> void:
	if state == null or mode != "game":
		return
	var payload := JSON.stringify(state.export_state())
	# localStorage is synchronous; IDBFS flushes asynchronously and can be
	# interrupted by an immediate reload after hatching or reaching the ending.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.setItem('" + WEB_SAVE_KEY + "', " + JSON.stringify(payload) + "); } catch(e) {}", true)
	# Atomic replace: interrupted writes cannot truncate the previous save.
	var file := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(payload)
		file.close()
		DirAccess.rename_absolute(SAVE_PATH + ".tmp", SAVE_PATH)
		if OS.has_feature("web"):
			JavaScriptBridge.force_fs_sync()

func read_saved_text() -> String:
	if OS.has_feature("web"):
		var stored = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('" + WEB_SAVE_KEY + "') || '';}catch(e){return '';}})()", true)
		if stored is String and not stored.is_empty():
			return stored
	return FileAccess.get_file_as_string(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""

