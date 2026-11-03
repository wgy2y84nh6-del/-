class_name HomeWorld
extends Control

const PET_DISPLAY_SCALE := 1.25

signal food_pressed(organ: String)
signal pet_pressed(index: int)
signal pet_released

var state: ParasiteGame
var art: HomeArt
var clock := 0.0
var held_pointer := -99
var font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = load("res://assets/fonts/DejaVuSans.ttf")

func _process(dt: float) -> void:
	if state and not state.paused:
		clock += dt
	queue_redraw()

func _draw() -> void:
	if state == null or art == null:
		return
	var scale_factor := size.x / 320.0
	var backdrop: String
	if not state.result.is_empty():
		backdrop = HomeArt.ENDINGS[state.result]
	elif state.view == "human":
		backdrop = HomeArt.PEOPLE[clampi(state.live_count(), 1, 3) - 1]
	else:
		backdrop = HomeArt.ORGANS[state.view]
	draw_texture_rect(art.tex(backdrop), Rect2(Vector2.ZERO, size), false)
	if state.view == "human" or not state.result.is_empty():
		return
	for p in state.pets:
		if not p.alive or p.organ != state.view:
			continue
		var f := art.frame(p)
		var sprite := parasite_rect(p, f)
		draw_texture_rect(art.tex(art.pet_file(p, f)), Rect2(sprite.position * scale_factor, sprite.size * scale_factor), false)
	if state.egg_left >= 0 and state.view == "heart":
		var f := int(clock / 0.55) % 2
		draw_texture_rect(art.tex(HomeArt.EGGS[f]), Rect2(Vector2(232, 126) * scale_factor, Vector2(44, 44) * scale_factor), false)
	if state.available_food.get(state.view, false):
		draw_texture_rect(art.tex("Еда_Для_Паразитов.png"), Rect2(HomeArt.FOOD_POSITION[state.view] * scale_factor, Vector2(32, 32) * scale_factor), false)
	if state.petting and state.pets[state.selected].alive and state.pets[state.selected].organ == state.view:
		var base := art.anchor(state.pets[state.selected])
		for i in range(3):
			var sway := sin(clock * 3.0 + i * 1.9) * 2.0
			var lift := sin(clock * 2.2 + i) * 2.5
			var point := base + Vector2(8 + i * 26 + sway, -6 - (i % 2) * 11 - lift)
			draw_texture_rect(art.tex("Сердечко.png"), Rect2(point * scale_factor, Vector2(27, 27) * scale_factor), false)

func parasite_rect(p: Dictionary, frame: int) -> Rect2:
	# Side slots for newborns keep their existing size and position.
	if p.organ == "heart" and p.id > 1:
		return Rect2(art.anchor(p) + art.frame_offset(p, frame), Vector2(96, 96))
	# Enlarge only the parasite around its existing center and foot baseline.
	var sprite_size := Vector2(96, 96) * PET_DISPLAY_SCALE
	var origin := art.anchor(p) + Vector2(48, 84) * (1.0 - PET_DISPLAY_SCALE) + art.frame_offset(p, frame) * PET_DISPLAY_SCALE
	return Rect2(origin, sprite_size)

func _gui_input(event: InputEvent) -> void:
	if state == null or state.paused or not state.result.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_at(event.position)
		else:
			release()
		accept_event()

func press_at(point: Vector2) -> void:
	var local := point / (size.x / 320.0)
	if state.available_food.get(state.view, false):
		var r := Rect2(HomeArt.FOOD_POSITION[state.view], Vector2(32, 32)).grow(5)
		if r.has_point(local):
			food_pressed.emit(state.view)
			queue_redraw() # This frame reflects the now-cleared boolean food slot.
			return
	for i in range(state.pets.size() - 1, -1, -1):
		var p: Dictionary = state.pets[i]
		if p.alive and p.organ == state.view and parasite_rect(p, art.frame(p)).has_point(local):
			held_pointer = i
			pet_pressed.emit(i)
			return

func release() -> void:
	held_pointer = -99
	pet_released.emit()
	queue_redraw()

