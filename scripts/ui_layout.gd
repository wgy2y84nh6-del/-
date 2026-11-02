extends RefCounted
## All coordinates are design pixels on a 1600x900 canvas.
## Anchors are (left, top, right, bottom); offsets are calculated from Rect2.

const DESIGN := Vector2(1600, 900)
const TOP_LEFT := Vector4(0, 0, 0, 0)
const TOP_RIGHT := Vector4(1, 0, 1, 0)
const TOP_CENTER := Vector4(0.5, 0, 0.5, 0)
const BOTTOM_LEFT := Vector4(0, 1, 0, 1)
const BOTTOM_RIGHT := Vector4(1, 1, 1, 1)
const BOTTOM_CENTER := Vector4(0.5, 1, 0.5, 1)
const CENTER := Vector4(0.5, 0.5, 0.5, 0.5)

const AREAS := {
	"header": {"rect": Rect2(16, 8, 1568, 82), "anchors": Vector4(0, 0, 1, 0)},
	"logo": {"rect": Rect2(32, 13, 266.4, 72), "anchors": TOP_LEFT},
	"view": {"rect": Rect2(512, 17, 236.8, 64), "anchors": TOP_CENTER},
	"pause": {"rect": Rect2(812, 21, 94.5, 56), "anchors": TOP_CENTER},
	"help": {"rect": Rect2(922.5, 21, 56, 56), "anchors": TOP_CENTER},
	"audio": {"rect": Rect2(994.5, 21, 94.5, 56), "anchors": TOP_CENTER},
	"human_meter": {"rect": Rect2(1224, 20.8, 337.2, 56.4), "anchors": TOP_RIGHT},
	"human_percent": {"rect": Rect2(1500, 16.8, 60, 30), "anchors": TOP_RIGHT},
	"notice": {"rect": Rect2(400, 112, 820, 70), "anchors": Vector4(0, 0, 1, 0)},
	"pet_card": {"rect": Rect2(16, 112, 360, 470), "anchors": TOP_LEFT},
	"family_panel": {"rect": Rect2(16, 598, 360, 176), "anchors": BOTTOM_LEFT},
	"world_frame": {"rect": Rect2(400, 196, 820, 578), "anchors": Vector4(0, 0, 1, 1)},
	"world": {"rect": Rect2(410, 220, 800, 450), "anchors": CENTER},
	"care_panel": {"rect": Rect2(1240, 112, 344, 662), "anchors": TOP_RIGHT},
	"footer": {"rect": Rect2(16, 792, 1568, 92), "anchors": Vector4(0, 1, 1, 1)},
	"feed": {"rect": Rect2(1264, 196, 296, 80), "anchors": TOP_RIGHT},
	"pet": {"rect": Rect2(1264, 296, 296, 80), "anchors": TOP_RIGHT},
	"sleep": {"rect": Rect2(1264, 396, 296, 80), "anchors": TOP_RIGHT},
	"move": {"rect": Rect2(1264, 624, 296, 80), "anchors": TOP_RIGHT},
	"family0": {"rect": Rect2(40, 642, 148, 40), "anchors": BOTTOM_LEFT},
	"family1": {"rect": Rect2(204, 642, 148, 40), "anchors": BOTTOM_LEFT},
	"family2": {"rect": Rect2(40, 698, 148, 40), "anchors": BOTTOM_LEFT},
	"visit": {"rect": Rect2(204, 698, 148, 40), "anchors": BOTTOM_LEFT},
	"human": {"rect": Rect2(49.6, 806, 236.8, 64), "anchors": BOTTOM_LEFT},
	"heart": {"rect": Rect2(302.4, 806, 236.8, 64), "anchors": BOTTOM_LEFT},
	"brain": {"rect": Rect2(555.2, 806, 236.8, 64), "anchors": BOTTOM_CENTER},
	"gut": {"rect": Rect2(808, 806, 236.8, 64), "anchors": BOTTOM_CENTER},
	"menu": {"rect": Rect2(1060.8, 806, 236.8, 64), "anchors": BOTTOM_RIGHT},
	"restart": {"rect": Rect2(1313.6, 806, 236.8, 64), "anchors": BOTTOM_RIGHT},
	"menu_logo": {"rect": Rect2(420, 104, 760, 760.0 * 89.0 / 645.0), "anchors": TOP_CENTER},
	"menu_play": {"rect": Rect2(622.4, 276, 355.2, 96), "anchors": CENTER},
	"menu_settings": {"rect": Rect2(622.4, 396, 355.2, 96), "anchors": CENTER},
	"menu_music": {"rect": Rect2(622.4, 516, 355.2, 96), "anchors": CENTER},
	"menu_exit": {"rect": Rect2(622.4, 636, 355.2, 96), "anchors": CENTER},
	"settings_frame": {"rect": Rect2(410, 205, 780, 490), "anchors": CENTER},
	"music_art": {"rect": Rect2(524, 312, 552, 100), "anchors": CENTER},
	"music_slider": {"rect": Rect2(528, 368, 546, 40), "anchors": CENTER},
	"sound_art": {"rect": Rect2(524, 438, 552, 102), "anchors": CENTER},
	"sound_slider": {"rect": Rect2(528, 496, 546, 40), "anchors": CENTER},
	"audio_back": {"rect": Rect2(652, 590, 296, 80), "anchors": CENTER},
	"help_frame": {"rect": Rect2(410, 100, 780, 700), "anchors": CENTER},
	"help_hint": {"rect": Rect2(477.5, 192, 645, 89), "anchors": CENTER},
	"help_back": {"rect": Rect2(652, 692, 296, 80), "anchors": CENTER}
}

static func rect(key: String) -> Rect2:
	return AREAS[key].rect

static func apply(node: Control, key: String) -> void:
	var r: Rect2 = AREAS[key].rect
	node.position = r.position
	node.size = r.size
	pin(node, AREAS[key].anchors)
	node.set_meta("layout_id", key)

static func pin(node: Control, anchors: Vector4) -> void:
	var r := Rect2(node.position, node.size)
	var p := node.get_parent() as Control
	var parent_size: Vector2 = DESIGN if p == null else p.size
	node.anchor_left = anchors.x
	node.anchor_top = anchors.y
	node.anchor_right = anchors.z
	node.anchor_bottom = anchors.w
	node.offset_left = r.position.x - anchors.x * parent_size.x
	node.offset_top = r.position.y - anchors.y * parent_size.y
	node.offset_right = r.end.x - anchors.z * parent_size.x
	node.offset_bottom = r.end.y - anchors.w * parent_size.y

static func infer(r: Rect2, mode: String, modal: bool) -> Vector4:
	if modal:
		return CENTER
	if mode == "menu":
		return BOTTOM_CENTER if r.position.y > 780 else CENTER
	if r.position.y >= 790:
		return BOTTOM_LEFT
	if r.position.x >= 1240:
		return TOP_RIGHT
	if r.position.x < 400:
		return BOTTOM_LEFT if r.position.y >= 598 else TOP_LEFT
	return BOTTOM_CENTER if r.position.y >= 680 else TOP_CENTER
