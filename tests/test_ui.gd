extends SceneTree
## Structural layout and pointer-release contracts on the real main scene.
var checks := 0
var failures: Array[String] = []

func check(value: bool, title: String) -> void:
	checks += 1
	if value:
		print("PASS: " + title)
	else:
		failures.append(title)
		push_error("FAIL: " + title)

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check(main.mode == "menu", "F5 main scene opens the menu")
	check(main.buttons.play.alignment == HORIZONTAL_ALIGNMENT_CENTER, "Play button uses genuine horizontal centering")
	check(main.buttons.play.size == Vector2(580, 86), "menu button follows reference rectangle")
	check(not main.buttons.has("sound") and main.buttons.has("music"), "menu removes Sound and preserves Music")
	check(main.buttons.settings.position.y == 391 and main.buttons.music.position.y == 532, "remaining menu buttons are evenly spaced")
	main.start_or_resume()
	await process_frame
	check(main.world.size == Vector2(800, 450), "organ image has unchanged 16:9 aspect")
	check(main.world.position == Vector2(410, 225), "world position is independent of text alignment")
	check(main.labels.view.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and main.labels.view.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "organ heading is centered in both dimensions")
	var centered := true
	for key in ["feed", "pet", "sleep", "human", "heart", "brain", "gut", "restart"]:
		centered = centered and main.buttons[key].alignment == HORIZONTAL_ALIGNMENT_CENTER
	check(centered, "all game-action and navigation button texts are centered")
	check(not main.buttons.has("wash") and main.buttons.pet.text == "Гладить", "care removes Wash and pet label contains only Гладить")
	check(main.buttons.pet.position == Vector2(1264, 305) and main.buttons.sleep.position == Vector2(1264, 421), "care buttons reflow without moving sleep or other panels")
	for i in range(3):
		main.state.pets[0].age = i * 0.55
		main.refresh()
		check(main.portrait.position.y >= 165, "portrait does not overlap the name, phase %d" % i)
	check(main.bars.hunger.size.y <= 20, "stat bars fit between their labels")
	main.state.set_view("heart")
	main.state.start_petting()
	main.navigate("human")
	check(not main.state.petting, "navigation immediately clears hearts")
	var positions: Dictionary = {}
	for key in ["feed", "human", "visit"]:
		positions[key] = main.buttons[key].position
	for key in ["heart", "brain", "gut", "human"]:
		main.navigate(key)
	var fixed := true
	for key in positions:
		fixed = fixed and positions[key] == main.buttons[key].position
	check(fixed, "care, family and navigation stay in place on every screen")
	main.show_settings()
	check(main.state.paused and is_instance_valid(main.overlay), "settings pauses gameplay")
	main.close_overlay()
	check(not main.state.paused, "closing settings resumes an active game")
	main.state.paused = true
	main.show_help()
	main.close_overlay()
	check(main.state.paused, "closing help preserves a pre-existing pause")
	check(main.audio.layers.size() == 3 and main.audio.layers.all(func(layer: AudioStreamPlayer): return layer.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD), "three music themes are imported as continuous loops")
	main.state.paused = false
	main.state.pets[0].hunger = 0
	main.state.pets[0].health = 0.1
	main._process(0.1)
	check(main.state.result == "loss" and is_instance_valid(main.overlay), "starvation opens actual bad-ending UI")
	main.restart_game()
	check(main.state.pets.size() == 1 and main.state.food == 6 and main.state.result.is_empty() and not main.state.paused, "restart fully restores the playable initial state")
	main.queue_free()
	await process_frame
	print("RESULT: %d UI checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
