class_name HomeArt
extends RefCounted
## Original filenames are retained verbatim, including the supplied frame suffixes.

const ROOT := "res://assets/original/"
const ORGANS := {"heart": "Сердце_.png", "brain": "Мозг.png", "gut": "Кишки.png"}
const PEOPLE := ["Человек_Фон_1_Стадия_1_Личинка.png", "Человек_Фон_2_Стадия_2_Личинки.png", "Человек_Фон_3_Стадия_3_Личинки.png"]
const NORMAL := [
	["1_Паразит_1_Анимация.png", "1_Паразит_2_Анимация 1.png"],
	["2_Паразит_1_Анимация.png", "2_Паразит_2_Анимация.png"],
	["3_Паразит_1_Анимация.png", "3_Паразит_2_Анимация.png"]]
const SLEEP := [
	["1_Спит_Паразит_1_Анимация.png", "1_Спит_Паразит_2_Анимация 1.png"],
	["2_Спит_Паразит_1_Анимация.png", "2_Спит_Паразит_2_Анимация.png"],
	["3_Спит_Паразит_1_Анимация.png", "3_Спит_Паразит_2_Анимация.png"]]
const EGGS := ["Яйцо_1_Анимация.png", "Яйцо_2_Анимация.png"]
const ENDINGS := {"win": "Хорошая_Концовка_Человек_Умер.png", "loss": "Плохая_Концовка_Паразит_Умер.png"}

# Rectangles in the ORIGINAL 320×180 organ image. Never derived from UI text.
# Reference #3: visible footprint at y=126; #4: y=126; #5: y=162.
const PLACEMENT := {"heart": Vector2(112, 42), "brain": Vector2(112, 42), "gut": Vector2(112, 78)}
const FOOD_POSITION := {"brain": Vector2(266, 30), "gut": Vector2(265, 30)}
var textures: Dictionary = {}

func _init() -> void:
	for file in ORGANS.values() + PEOPLE + EGGS + ENDINGS.values() + ["Еда_Для_Паразитов.png", "Сердечко.png"]:
		textures[file] = load(ROOT + file)
	for pair in NORMAL + SLEEP:
		for file in pair:
			textures[file] = load(ROOT + file)

func tex(file: String) -> Texture2D:
	return textures[file]

func pet_file(p: Dictionary, frame: int) -> String:
	return (SLEEP if p.sleeping else NORMAL)[int(p.id) - 1][frame]

func frame(p: Dictionary) -> int:
	return int((float(p.age) + (int(p.id) - 1) * 0.19) / 0.55) % 2

func anchor(p: Dictionary) -> Vector2:
	if p.organ == "heart" and p.id > 1:
		# Temporary residents occupy separate, deterministic 96px slots.
		return Vector2(8, 48) if p.id == 2 else Vector2(216, 48)
	return PLACEMENT[p.organ]

func frame_offset(p: Dictionary, f: int) -> Vector2:
	# Supplied awake frame 2 has its ground at y=96, frame 1 at y=84.
	# Translate the transparent canvas, never resize the sprite: same footprint.
	return Vector2(0, -12) if f == 1 and not p.sleeping else Vector2.ZERO

