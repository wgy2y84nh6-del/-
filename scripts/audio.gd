class_name HomeAudio
extends Node
## All music/effects are original synthesized game sounds; no body recordings.

var music_volume := 0.45
var effects_volume := 0.65
var music: AudioStreamPlayer
var effects: Array[AudioStreamPlayer] = []
var stage := 0
var unlocked := false
var layers: Array[AudioStreamPlayer] = []
var weights := [0.0, 0.0, 0.0]

func _ready() -> void:
	for i in range(3):
		var layer := AudioStreamPlayer.new()
		layer.stream = load("res://assets/audio/music_%d.wav" % (i + 1))
		# Explicit runtime loop also documents the intended import mode.
		layer.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		layer.stream.loop_begin = 0
		layer.stream.loop_end = 264600
		add_child(layer)
		layers.append(layer)
	music = layers[0]
	for i in range(5):
		var player := AudioStreamPlayer.new()
		add_child(player)
		effects.append(player)
	load_settings()
	apply_volume()

func unlock() -> void:
	unlocked = true
	if not layers[0].playing:
		for layer in layers:
			layer.play()
		set_stage(1)

func set_stage(value: int) -> void:
	value = clampi(value, 1, 3)
	if not unlocked or stage == value and music.playing:
		return
	stage = value
	music = layers[stage - 1]
	apply_volume()

func _process(dt: float) -> void:
	for i in range(3):
		weights[i] = move_toward(weights[i], 1.0 if stage == i + 1 else 0.0, dt / 2.5)
	apply_volume()

func effect(kind: String) -> void:
	if not unlocked:
		return
	var file := "res://assets/audio/%s.wav" % kind
	if not ResourceLoader.exists(file):
		file = "res://assets/audio/click.wav"
	var player := effects[0]
	for candidate in effects:
		if not candidate.playing:
			player = candidate
			break
	player.stream = load(file)
	player.volume_db = linear_to_db(maxf(0.0001, effects_volume))
	player.play()

func apply_volume() -> void:
	for i in range(layers.size()):
		layers[i].volume_db = linear_to_db(maxf(0.0001, music_volume * weights[i]))
	for p in effects:
		p.volume_db = linear_to_db(maxf(0.0001, effects_volume))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "effects", effects_volume)
	cfg.save("user://settings.cfg")
	if OS.has_feature("web"):
		var payload := JSON.stringify({"music": music_volume, "effects": effects_volume})
		JavaScriptBridge.eval("try { localStorage.setItem('you-are-my-home:audio:v1', " + JSON.stringify(payload) + "); } catch(e) {}", true)
		JavaScriptBridge.force_fs_sync()

func load_settings() -> void:
	if OS.has_feature("web"):
		var stored = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('you-are-my-home:audio:v1') || '';}catch(e){return '';}})()", true)
		if stored is String and not stored.is_empty():
			var parsed = JSON.parse_string(stored)
			if parsed is Dictionary and parsed.get("music") is float and parsed.get("effects") is float:
				music_volume = clampf(parsed.music, 0, 1)
				effects_volume = clampf(parsed.effects, 0, 1)
				return
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		music_volume = clampf(float(cfg.get_value("audio", "music", 0.45)), 0, 1)
		effects_volume = clampf(float(cfg.get_value("audio", "effects", 0.65)), 0, 1)

