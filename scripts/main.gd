extends Control

const BACK := Color("201629")
const PANEL := Color("302037")
const PINK := Color("b786b4")
const INK := Color("ffced4")
const MUTED := Color("b786b4")
const ORGAN_NAMES := {"heart": "СЕРДЦЕ", "brain": "МОЗГ", "gut": "КИШЕЧНИК", "human": "ЧЕЛОВЕК"}
const SAVE_PATH := "user://home_save.json"
const WEB_SAVE_KEY := "you-are-my-home:save:v1"
const StateClass = preload("res://scripts/game_state.gd")
const ArtClass = preload("res://scripts/art.gd")
const WorldClass = preload("res://scripts/world.gd")
const AudioClass = preload("res://scripts/audio.gd")
const SkinClass = preload("res://scripts/ui_skin.gd")
const MeterClass = preload("res://scripts/ui_meter.gd")
const SliderClass = preload("res://scripts/ui_slider.gd")

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
var skin
var ui_images: Dictionary = {}

func _ready() -> void:
	skin = SkinClass.new()
	body_font = skin.font
	title_font = skin.heading
	state = StateClass.new()
	state.event.connect(_on_event)
	art = ArtClass.new()
	audio = AudioClass.new()
	add_child(audio)
	page = Control.new()
	page.size = Vector2(1600, 900)
	page.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	if skin:
		page.draw_texture_rect(skin.tex("background"), Rect2(0, 0, 1600, 900), false)

func clear_content() -> void:
	close_overlay(false)
	if is_instance_valid(content):
		remove_child_from_page(content)
	labels.clear()
	bars.clear()
	buttons.clear()
	family.clear()
	ui_images.clear()
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

func style(fill: Color, line: Color, _primary := false) -> StyleBoxFlat:
	return skin.frame(fill, line)

func bar_style(fill: Color, line: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = line
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.corner_detail = 1
	return box

func button(key: String, title: String, rect: Rect2, action: Callable, _primary := false, parent: Control = null, font_size := 28) -> Button:
	var b := Button.new()
	b.name = key
	b.position = rect.position
	b.size = rect.size
	b.text = title
	b.tooltip_text = title
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", font_size)
	b.set_meta("label_size", font_size)
	(parent if parent else content).add_child(b)
	skin.apply_button(b, key if SkinClass.FILES.has(key) else "")
	skin.fit_button(b)
	b.pressed.connect(func():
		audio.unlock()
		audio.effect("click")
		action.call())
	buttons[key] = b
	return b

func build_menu() -> void:
	mode = "menu"
	state.paused = true
	clear_content()
	skin.image(content, "menu_logo", Rect2(316.25, 88, 967.5, 133.5))
	button("play", "Играть", Rect2(600.2, 260, 399.6, 108), start_or_resume, true, null, 48)
	button("settings", "Настройки", Rect2(600.2, 390, 399.6, 108), show_settings, false, null, 44)
	button("music", "Музыка", Rect2(600.2, 520, 399.6, 108), show_settings, false, null, 80)
	button("exit", "Выход", Rect2(600.2, 650, 399.6, 108), show_exit, false, null, 48)
	text_node("ПАРАЗИТ-ТАМАГОЧИ", Rect2(510, 828, 580, 30), 22).modulate = MUTED

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
	skin.image(content, "header", Rect2(26, 14, 1548, 213.6))
	skin.image(content, "logo", Rect2(58, 44, 296, 80))
	var view_frame := Panel.new()
	view_frame.position = Vector2(420, 48)
	view_frame.size = Vector2(266.4, 72)
	view_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_frame.add_theme_stylebox_override("panel", style(Color("503650"), PINK))
	content.add_child(view_frame)
	ui_images["view_heart"] = skin.image(content, "view_heart", Rect2(420, 48, 266.4, 72))
	labels["view"] = text_node("СЕРДЦЕ", Rect2(420, 48, 266.4, 72), 36, true, true)
	button("pause", "Ⅱ", Rect2(730, 54, 101.25, 60), toggle_pause, false, null, 40)
	button("help", "?", Rect2(850, 54, 101.25, 60), show_help, false, null, 44)
	button("audio", "Музыка и звук", Rect2(970, 54, 101.25, 60), show_settings, false, null, 20)
	var human_bar = MeterClass.new()
	human_bar.configure(skin, "human")
	human_bar.position = Vector2(1188, 55)
	human_bar.size = Vector2(337.2, 56.4)
	content.add_child(human_bar)
	bars["human"] = human_bar
	labels["human"] = text_node("ЧЕЛОВЕК · СТАДИЯ 1", Rect2(1188, 55, 337.2, 30), 20)
	labels["human"].visible = false
	labels["notice"] = text_node(state.notice, Rect2(126, 147, 1348, 48), 25)
	labels["notice"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_images["card"] = skin.image(content, "card0", Rect2(24, 244, 274.75, 518))
	labels["name"] = text_node("Пух", Rect2(44, 252, 234, 34), 28)
	labels["name"].visible = false
	portrait = TextureRect.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	content.add_child(portrait)
	labels["home"] = text_node("Дома в сердце", Rect2(42, 449, 238, 26), 24)
	var stat_keys := ["hunger", "energy", "joy", "health"]
	for i in range(4):
		var y := 492.0 + i * 54.0
		var bar = MeterClass.new()
		bar.configure(skin, stat_keys[i])
		bar.position = Vector2(51, y)
		bar.size = Vector2(220.8, 40.0 if i == 1 else 36.8)
		content.add_child(bar)
		bars[stat_keys[i]] = bar
		labels[stat_keys[i]] = text_node("85%", Rect2(218, y - 4, 54, 23), 24)
		if i == 3:
			text_node("Здоровье", Rect2(51, y - 5, 158, 23), 22, false)
	skin.image(content, "family", Rect2(324, 244, 188.4, 333.6))
	for i in range(3):
		var index := i
		var b := button("family%d" % i, ["Пух", "Лилу", "Ростик"][i], Rect2(344.2, 295 + i * 56, 148, 40), func(): state.select_pet(index), false, null, 22)
		family.append(b)
		labels["family_status%d" % i] = text_node("", Rect2(332, 336 + i * 56, 172, 16), 15)
		labels["family_status%d" % i].visible = false
	button("visit", "К питомцу", Rect2(344.2, 489, 148, 40), func(): navigate(state.pets[state.selected].organ), false, null, 18)
	labels["family_count"] = text_node("1 / 3", Rect2(332, 541, 172, 24), 24)
	labels["timers"] = text_node("", Rect2(532, 246, 688.5, 36), 25)
	skin.image(content, "world_frame", Rect2(532, 300, 688.5, 378))
	world = WorldClass.new()
	world.state = state
	world.art = art
	world.position = Vector2(556.25, 309)
	world.size = Vector2(640, 360)
	world.clip_contents = true
	world.food_pressed.connect(func(organ: String): state.collect(organ))
	world.pet_pressed.connect(func(index: int):
		state.select_pet(index)
		state.start_petting())
	world.pet_released.connect(stop_petting)
	content.add_child(world)
	var caption_panel := Panel.new()
	caption_panel.position = Vector2(553.75, 690)
	caption_panel.size = Vector2(645, 89)
	caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_panel.add_theme_stylebox_override("panel", style(PANEL, PINK))
	content.add_child(caption_panel)
	ui_images["food_hint"] = skin.image(content, "food_hint", Rect2(553.75, 690, 645, 89))
	labels["caption"] = text_node("", Rect2(568, 696, 616, 77), 23)
	labels["caption"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skin.image(content, "care", Rect2(1293, 244, 274.75, 518))
	button("feed", "Кормить", Rect2(1315, 303, 236.8, 64), func(): state.feed(), true, null, 28)
	var pet_button := button("pet", "Гладить", Rect2(1315, 387, 236.8, 64), func(): pass, false, null, 28)
	pet_button.button_down.connect(func():
		audio.unlock()
		state.start_petting())
	pet_button.button_up.connect(stop_petting)
	pet_button.mouse_exited.connect(stop_petting)
	button("sleep", "Спать", Rect2(1315, 471, 236.8, 64), func(): state.sleep_toggle(), false, null, 44)
	labels["food"] = text_node("Еда · 6", Rect2(1310, 552, 242, 36), 30, true, true)
	text_node("Кормление — 3 еды", Rect2(1303, 594, 254, 27), 21)
	button("move", "Переселить", Rect2(1315, 646, 236.8, 64), func(): state.relocate(), false, null, 28)
	labels["count"] = text_node("Паразитов · 1 / 3", Rect2(1303, 725, 254, 26), 21)
	button("human", "Человек", Rect2(40, 810, 236.8, 64), func(): navigate("human"), false, null, 28)
	button("heart", "Сердце", Rect2(296.8, 810, 236.8, 64), func(): navigate("heart"), false, null, 28)
	button("brain", "Мозг", Rect2(553.6, 810, 236.8, 64), func(): navigate("brain"), false, null, 48)
	button("gut", "Кишечник", Rect2(810.4, 810, 236.8, 64), func(): navigate("gut"), false, null, 28)
	button("menu", "Меню", Rect2(1067.2, 810, 236.8, 64), func():
		save_game()
		build_menu(), false, null, 48)
	button("restart", "Заново", Rect2(1324, 810, 236.8, 64), confirm_restart, false, null, 28)
	refresh()

func refresh() -> void:
	if mode != "game" or labels.is_empty():
		return
	if not state.pets[state.selected].alive:
		state.selected = 0
	var p: Dictionary = state.pets[state.selected]
	labels["name"].text = p.name
	ui_images["card"].texture = skin.atlas("card%d" % (int(p.id) - 1))
	labels["view"].text = ORGAN_NAMES[state.view]
	ui_images["view_heart"].visible = state.view == "heart"
	labels["view"].visible = state.view != "heart"
	labels["home"].text = ("Сладко спит · " if p.sleeping else "Дома · ") + ORGAN_NAMES[p.organ].to_lower()
	labels["notice"].text = state.notice
	labels["food"].text = "Еда · %d" % state.food
	labels["count"].text = "Паразитов · %d / 3" % state.live_count()
	labels["family_count"].text = "%d / 3" % state.live_count()
	labels["human"].text = "ЧЕЛОВЕК · СТАДИЯ %d" % maxi(1, state.live_count())
	bars["human"].set_stage(maxi(1, state.live_count()))
	bars["human"].value = 100 - (maxi(1, state.live_count()) - 1) * 32
	if state.final_left >= 0:
		bars["human"].value = 36 * state.final_left / 40.0
	for key in ["hunger", "energy", "joy", "health"]:
		bars[key].value = p[key]
		labels[key].text = "%d%%" % ceili(p[key])
	var f := art.frame(p)
	portrait.texture = art.tex(art.pet_file(p, f))
	portrait.position = Vector2(98.975, 330) + art.frame_offset(p, f) * 1.3
	portrait.size = Vector2(96, 96) * 1.3
	for i in range(3):
		family[i].disabled = i >= state.pets.size() or not state.pets[i].alive
		skin.mark(family[i], i == state.selected)
		labels["family_status%d" % i].text = "Появится позже" if i >= state.pets.size() else ("Ждём замену" if not state.pets[i].alive else ORGAN_NAMES[state.pets[i].organ].capitalize())
	buttons["sleep"].text = "Разбудить" if p.sleeping else "Спать"
	skin.apply_button(buttons["sleep"], "" if p.sleeping else "sleep")
	buttons["pause"].text = "▶" if state.paused else "Ⅱ"
	skin.apply_button(buttons["pause"], "continue" if state.paused else "pause")
	buttons["feed"].disabled = state.paused or not state.result.is_empty()
	buttons["pet"].disabled = state.paused or not state.result.is_empty()
	buttons["sleep"].disabled = state.paused or not state.result.is_empty()
	buttons["move"].disabled = state.paused or p.id == 1 or p.organ != "heart" or not state.result.is_empty()
	if p.id > 1 and p.organ == "heart":
		buttons["move"].text = "Переселить\n" + ("в мозг" if p.id == 2 else "в кишечник")
	else:
		buttons["move"].text = "Дома · " + ORGAN_NAMES[p.organ].to_lower()
	skin.fit_button(buttons["move"])
	skin.fit_button(buttons["sleep"])
	for key in ["human", "heart", "brain", "gut"]:
		skin.mark(buttons[key], state.view == key)
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
	var show_food_art: bool = state.view in ["brain", "gut"] and state.available_food[state.view]
	ui_images["food_hint"].visible = show_food_art
	labels["caption"].visible = not show_food_art

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
	shade.color = Color(0.125, 0.086, 0.16, 0.90)
	shade.size = overlay.size
	overlay.add_child(shade)
	var box := Panel.new()
	box.position = Vector2(410, (900 - height) / 2.0)
	box.size = Vector2(780, height)
	box.add_theme_stylebox_override("panel", style(PANEL, PINK, true))
	overlay.add_child(box)
	text_node(title, Rect2(430, box.position.y + 22, 740, 64), 40, true, true, overlay)
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
	skin.image(ui, "volume_music", Rect2(524, 318, 552, 100))
	add_slider(Vector2(528, 374), audio.music_volume, func(value: float):
		audio.music_volume = value
		audio.apply_volume()
		audio.save_settings(), ui)
	skin.image(ui, "volume_sound", Rect2(524, 448, 552, 102))
	add_slider(Vector2(528, 506), audio.effects_volume, func(value: float):
		audio.effects_volume = value
		audio.apply_volume()
		audio.save_settings(), ui)
	button("audio_back", "Готово", Rect2(637.2, 591, 325.6, 80), close_overlay, true, ui, 48)

func add_slider(pos: Vector2, value: float, callback: Callable, parent: Control) -> void:
	var slider = SliderClass.new()
	slider.position = pos
	slider.size = Vector2(546, 40)
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.01
	slider.value = value
	slider.value_changed.connect(callback)
	parent.add_child(slider)

func show_help() -> void:
	var ui := make_overlay("Как обжиться внутри", 700)
	var instructions := "Собирай по одному шарику в мозгу и кишечнике.\nНовый цикл — каждые 7 секунд. Кормление стоит 3 еды.\n\nВыбери питомца слева. Корми, гладь и укладывай спать.\nУдерживай «Гладить» или самого питомца: появятся сердечки.\n\nПух откладывает яйцо раз в 50 секунд при сытости > 70%.\nЯйцо вылупляется за 20 секунд. Пересели Лилу в мозг,\nа Ростика — в кишечник кнопкой «Переселить».\n\nТри живых питомца запускают финал на 40 секунд.\nМладшие голодают быстрее. Пух может вырастить им замену.\n\n1 — кормить   4 — сон   Пробел — пауза\nH — человек   Q / W / E — органы   Esc — закрыть окно\nПрогресс сохраняется автоматически, офлайн-время не считается."
	text_node(instructions, Rect2(435, 208, 730, 430), 21, true, false, ui)
	button("help_back", "Понятно", Rect2(637.2, 670, 325.6, 80), close_overlay, true, ui, 48)

func confirm_restart() -> void:
	var ui := make_overlay("Начать заново?", 340)
	text_node("Текущая семья и запас еды будут сброшены.", Rect2(450, 395, 700, 50), 23, true, false, ui)
	button("restart_cancel", "Остаться", Rect2(480, 495, 300, 80), close_overlay, false, ui, 40)
	button("restart_confirm", "Новый дом", Rect2(820, 495, 300, 80), restart_game, true, ui, 40)

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
	button("ending_look", "Посмотреть", Rect2(480, 505, 300, 80), close_overlay, false, ui, 40)
	button("ending_again", "Начать заново", Rect2(820, 505, 300, 80), restart_game, true, ui, 40)

func show_exit() -> void:
	var ui := make_overlay("До встречи дома", 340)
	text_node("В браузере можно закрыть эту вкладку.\nПрогресс сохранён — семья дождётся тебя.", Rect2(450, 380, 700, 90), 23, true, false, ui)
	button("exit_back", "Остаться", Rect2(600, 505, 400, 80), close_overlay, true, ui, 40)

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

