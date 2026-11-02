extends SceneTree

var checks := 0
var failures: Array[String] = []
var geometry: Dictionary = {}

func check(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures.append(title)
		push_error(title)

func record(main: Control, key: String) -> void:
	var controls: Dictionary = {}
	var live: Array[Button] = []
	for name in main.buttons:
		var b = main.buttons[name]
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		controls[name] = {"x": b.position.x, "y": b.position.y, "w": b.size.x, "h": b.size.y}
		check(b.position.x >= 0 and b.position.y >= 0 and b.position.x + b.size.x <= 1600.1 and b.position.y + b.size.y <= 900.1, key + ": button stays on screen: " + name)
		live.append(b)
		if b.get_meta("art_skin", "") == "":
			var font: Font = b.get_theme_font("font")
			var font_size: int = b.get_theme_font_size("font_size")
			for line in b.text.split("\n"):
				check(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= b.size.x - 20, key + ": button text fits: " + name)
	for i in range(live.size()):
		for j in range(i + 1, live.size()):
			# Overlay controls intentionally cover the underlying screen.
			if live[i].get_parent() == live[j].get_parent():
				check(not Rect2(live[i].position, live[i].size).intersects(Rect2(live[j].position, live[j].size)), key + ": buttons do not overlap")
	geometry[key] = controls

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check(main.skin.textures.size() == 43, "All forty-three supplied PNGs are loaded")
	check(main.mode == "menu" and main.state.paused, "Menu opens without advancing the simulation")
	check(main.buttons.play.get_meta("art_skin") == "play" and main.buttons.settings.get_meta("art_skin") == "settings" and main.buttons.exit.get_meta("art_skin") == "exit", "Prepared menu images take priority")
	record(main, "menu")
	main.buttons.settings.pressed.emit()
	await process_frame
	check(is_instance_valid(main.overlay), "Settings button opens overlay")
	var sliders: Array[Node] = main.overlay.find_children("*", "HSlider", true, false)
	check(sliders.size() == 2, "Both volume controls are retained")
	sliders[0].value = 0.23
	sliders[1].value = 0.67
	check(absf(main.audio.music_volume - 0.23) < 0.001 and absf(main.audio.effects_volume - 0.67) < 0.001, "Original independent volume callbacks still work")
	record(main, "settings")
	main.buttons.audio_back.pressed.emit()
	await process_frame
	check(not is_instance_valid(main.overlay), "Settings can be closed")
	main.start_or_resume()
	main.restart_game()
	main.state.paused = true
	main.refresh()
	await process_frame
	check(main.world.size == Vector2(640, 360) and main.world.size.x / main.world.size.y == 16.0 / 9.0, "Original scene proportions are preserved")
	check(main.skin.region("card0").size.x / main.skin.region("card0").size.y == main.ui_images.card.size.x / main.ui_images.card.size.y, "Supplied portrait panel retains its proportions")
	check(main.bars.size() == 5, "All four needs and human status remain visible")
	record(main, "game")
	main.state.paused = false
	main.state.pets[0].hunger = 20.0
	main.state.food = 6
	main.buttons.feed.pressed.emit()
	check(main.state.pets[0].hunger == 62.0 and main.state.food == 3, "New feed image invokes the original feed action")
	main.buttons.sleep.pressed.emit()
	main.refresh()
	check(main.state.pets[0].sleeping and main.buttons.sleep.text == "Разбудить" and main.buttons.sleep.get_meta("art_skin") == "", "Sleep changes to a matching wake-up control")
	main.buttons.sleep.pressed.emit()
	main.refresh()
	check(not main.state.pets[0].sleeping and main.buttons.sleep.get_meta("art_skin") == "sleep", "Original sleep image returns when awake")
	main.buttons.pet.button_down.emit()
	check(main.state.petting, "Petting begins on button hold")
	main.buttons.pet.button_up.emit()
	check(not main.state.petting, "Petting stops on release")
	main.state.pets.append(main.state.make_pet(2))
	main.refresh()
	main.buttons.family1.pressed.emit()
	main.refresh()
	check(main.state.selected == 1 and main.ui_images.card.texture == main.skin.atlas("card1"), "Lilu selector switches to the supplied Lilu panel")
	main.buttons.move.pressed.emit()
	main.refresh()
	check(main.state.pets[1].organ == "brain", "Relocation still uses the original action")
	main.buttons.visit.pressed.emit()
	main.refresh()
	check(main.state.view == "brain" and main.labels.view.visible, "Visit and missing brain tab work")
	main.state.pets.append(main.state.make_pet(3))
	main.refresh()
	main.buttons.family2.pressed.emit()
	main.refresh()
	check(main.ui_images.card.texture == main.skin.atlas("card2"), "Rostik panel uses supplied artwork")
	main.buttons.move.pressed.emit()
	main.refresh()
	check(main.state.pets[2].organ == "gut" and main.bars.human.stage == 3, "Third relocation and third human-stage image work")
	for need in ["hunger", "energy", "joy", "health"]:
		for amount in [0.0, 25.0, 50.0, 75.0, 100.0]:
			main.state.pets[2][need] = amount
			main.refresh()
			check(main.bars[need].value == amount, "Artwork meter follows exact value: " + need)
	main.state.pets[2].health = 100.0
	main.state.pets[1].health = 0.0
	main._process(0.01)
	check(main.family[1].disabled and main.state.result.is_empty(), "Dead junior is disabled without a losing overlay")
	main.restart_game()
	main.state.pets[0].hunger = 0.0
	main.state.pets[0].health = 0.1
	main._process(0.1)
	check(main.state.result == "loss" and is_instance_valid(main.overlay), "Original loss opens the new modal skin")
	record(main, "loss")
	main.buttons.ending_again.pressed.emit()
	check(main.state.result.is_empty() and main.state.pets.size() == 1 and main.state.food == 6, "Restart from ending retains original reset behavior")
	main.state.pets.append(main.state.make_pet(2))
	main.state.pets.append(main.state.make_pet(3))
	main.state.final_left = 0.01
	main._process(0.02)
	check(main.state.result == "win" and is_instance_valid(main.overlay), "Original win opens the new modal skin")
	record(main, "win")
	main.buttons.ending_look.pressed.emit()
	check(not is_instance_valid(main.overlay), "Ending view can be revealed")
	main.restart_game()
	main.buttons.help.pressed.emit()
	await process_frame
	record(main, "help")
	main.buttons.help_back.pressed.emit()
	main.buttons.restart.pressed.emit()
	await process_frame
	record(main, "restart")
	main.buttons.restart_cancel.pressed.emit()
	check(not is_instance_valid(main.overlay) and not main.state.paused, "Cancel restores original running state")
	main.buttons.menu.pressed.emit()
	main.buttons.exit.pressed.emit()
	await process_frame
	record(main, "exit")
	main.buttons.exit_back.pressed.emit()
	check(main.mode == "menu" and not is_instance_valid(main.overlay), "Exit dialog still returns to menu")
	if not OS.get_environment("HOME_UI_TEST_OUTPUT").is_empty():
		FileAccess.open(OS.get_environment("HOME_UI_TEST_OUTPUT"), FileAccess.WRITE).store_string(JSON.stringify(geometry))
	for player in main.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.1).timeout
	main.queue_free()
	await create_timer(0.1).timeout
	print("RESULT: %d UI checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
