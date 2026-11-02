extends HSlider
## Native keyboard/pointer slider over the supplied music/sound artwork.

func _ready() -> void:
	for state in ["slider", "grabber_area", "grabber_area_highlight"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var transparent := Image.create(12, 32, false, Image.FORMAT_RGBA8)
	transparent.fill(Color.TRANSPARENT)
	var handle := ImageTexture.create_from_image(transparent)
	for state in ["grabber", "grabber_highlight", "grabber_disabled"]:
		add_theme_icon_override(state, handle)
	value_changed.connect(func(_value: float): queue_redraw())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	var x := 6.0 + (size.x - 12.0) * value
	draw_rect(Rect2(0, 2, x, size.y - 4), Color("f48ead"))
	draw_rect(Rect2(x - 6, -2, 12, size.y + 4), Color("ffced4"))
	if has_focus() or get_global_rect().has_point(get_global_mouse_position()):
		draw_rect(Rect2(x - 6, -2, 12, size.y + 4), Color("b786b4"), false, 2)
