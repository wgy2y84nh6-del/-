extends ProgressBar
## Exact Range value drives only the painted interior of the supplied bar.

var skin
var kind := "hunger"
var stage := 1

func configure(visual_skin, meter_kind: String) -> void:
	skin = visual_skin
	kind = meter_kind
	show_percentage = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("background", StyleBoxEmpty.new())
	add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	add_theme_font_size_override("font_size", 1)
	value_changed.connect(func(_value: float): queue_redraw())

func set_stage(new_stage: int) -> void:
	if stage != new_stage:
		stage = new_stage
		queue_redraw()

func _draw() -> void:
	if skin == null:
		return
	var key: String = "human%d" % stage if kind == "human" else kind
	var empty_key: String = "hunger_empty" if kind == "health" else key + "_empty"
	var full_key: String = "human1_full" if kind == "health" else key + "_full"
	var crop: Rect2 = skin.region(empty_key)
	var factor := size.x / crop.size.x
	if kind == "health":
		# No health artwork was supplied: reuse the user's empty bar border and
		# pink human-meter pixels, with a matching live label in main.gd.
		draw_texture_rect_region(skin.tex(empty_key), Rect2(Vector2(0, 22) * factor, Vector2(276, 24) * factor), Rect2(22, 87, 276, 24))
	else:
		draw_texture_rect_region(skin.tex(empty_key), Rect2(Vector2.ZERO, crop.size * factor), crop)
	var width := 273.0 * clampf(value / 100.0, 0.0, 1.0)
	if width > 0:
		var pixels := Rect2(24, 89, width, 20)
		draw_texture_rect_region(skin.tex(full_key), Rect2((pixels.position - crop.position) * factor, pixels.size * factor), pixels)
