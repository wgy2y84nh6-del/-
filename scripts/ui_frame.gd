extends Control
## Size-adaptive frame assembled from the original PNG's unchanged pieces.
## Only the blank fill and straight edge lengths change; corners and lettering
## are always uniformly scaled, never stretched with the panel body.

var skin
var art_key := "header"
var pixel_scale := 2.0
var show_title := false
var title_scale := 2.0
var title_offset := Vector2(24, 10)
var center_title := false

func configure(visual_skin, key: String) -> void:
	skin = visual_skin
	art_key = key
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)

func set_art(key: String) -> void:
	if art_key != key:
		art_key = key
		queue_redraw()

func _draw() -> void:
	if skin == null or size.x <= 16 or size.y <= 16:
		return
	var data: Dictionary = skin.frame_regions[art_key]
	var raw: Array = data.frame
	var r := Rect2(raw[0], raw[1], raw[2], raw[3])
	var c := float(data.border)
	var d := c * pixel_scale
	var texture: Texture2D = skin.tex(art_key)
	var sample: Array = data.fill
	draw_texture_rect_region(texture, Rect2(d, d, size.x - 2 * d, size.y - 2 * d), Rect2(sample[0], sample[1], 1, 1))
	# Four original corner patches; no deformation of their shape.
	draw_texture_rect_region(texture, Rect2(0, 0, d, d), Rect2(r.position, Vector2(c, c)))
	draw_texture_rect_region(texture, Rect2(size.x - d, 0, d, d), Rect2(r.end.x - c, r.position.y, c, c))
	draw_texture_rect_region(texture, Rect2(0, size.y - d, d, d), Rect2(r.position.x, r.end.y - c, c, c))
	draw_texture_rect_region(texture, Rect2(size.x - d, size.y - d, d, d), Rect2(r.end - Vector2(c, c), Vector2(c, c)))
	# These source strips contain only a straight line and constant fill.
	draw_texture_rect_region(texture, Rect2(d, 0, size.x - 2 * d, d), Rect2(r.position.x + c, r.position.y, r.size.x - 2 * c, c))
	draw_texture_rect_region(texture, Rect2(d, size.y - d, size.x - 2 * d, d), Rect2(r.position.x + c, r.end.y - c, r.size.x - 2 * c, c))
	draw_texture_rect_region(texture, Rect2(0, d, d, size.y - 2 * d), Rect2(r.position.x, r.position.y + c, c, r.size.y - 2 * c))
	draw_texture_rect_region(texture, Rect2(size.x - d, d, d, size.y - 2 * d), Rect2(r.end.x - c, r.position.y + c, c, r.size.y - 2 * c))
	if show_title and data.title != null:
		var t: Array = data.title
		var source := Rect2(t[0], t[1], t[2] - t[0], t[3] - t[1])
		var target_size := source.size * title_scale
		var position_in_frame := title_offset
		if center_title:
			position_in_frame.x = (size.x - target_size.x) / 2.0
		draw_texture_rect_region(texture, Rect2(position_in_frame, target_size), source)
