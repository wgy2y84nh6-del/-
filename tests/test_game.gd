extends SceneTree
## Run: godot --headless --path . --script tests/test_game.gd
const Model = preload("res://scripts/game_state.gd")
const Art = preload("res://scripts/art.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures.append(title)
		push_error("FAIL: " + title)
	else:
		print("PASS: " + title)

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	var s = Model.new()
	check(s.pets.size() == 1 and s.pets[0].organ == "heart", "first resident starts in heart")
	check(s.available_food == {"brain": true, "gut": true}, "one independent food slot in each food organ")
	var food: int = s.food
	check(s.collect("brain") and s.food == food + 1 and not s.available_food.brain, "collect adds exactly one and immediately clears slot")
	check(not s.collect("brain") and s.food == food + 1, "double collection rejected")
	check(not s.collect("heart"), "no food in heart")
	for i in range(500):
		s.set_view(["human", "heart", "brain", "gut"][i % 4])
	check(not s.available_food.brain and s.available_food.gut and s.food == food + 1 and s.elapsed == 0, "500 navigations preserve inventory, slots and clocks")
	s.tick(6.9)
	check(not s.available_food.brain, "no early respawn")
	s.tick(0.1)
	check(s.available_food.brain, "respawn at next seven-second cycle")
	s.tick(21)
	check(s.collect("gut") and not s.collect("gut"), "missed cycles do not stack food")
	food = s.food
	s.pets[0].hunger = 20
	check(s.feed() and s.food == food - 3 and s.pets[0].hunger == 62, "feeding costs three and restores hunger")
	s.food = 2
	check(not s.feed() and s.food == 2, "insufficient food cannot be consumed")
	check(not s.pets[0].has("clean"), "cleanliness is absent from current game state")
	var drain_test = Model.new()
	drain_test.tick(1)
	check(absf(drain_test.pets[0].hunger - 84.44) < 0.0001, "base hunger drain is 0.56 points per second")
	check(absf(drain_test.pets[0].energy - 84.76) < 0.0001 and absf(drain_test.pets[0].joy - 84.8) < 0.0001, "energy and joy decay remain unchanged")
	s.set_view("heart")
	s.pets[0].joy = 25
	s.start_petting()
	s.tick(1)
	check(s.petting and s.pets[0].joy > 42, "held petting restores joy")
	s.set_view("human")
	check(not s.petting, "navigation ends petting")
	check(not s.start_petting(), "cannot pet invisible resident")
	s.pets[0].energy = 20
	s.sleep_toggle()
	s.tick(2)
	check(s.pets[0].sleeping and s.pets[0].energy > 35, "sleep restores energy on another screen")
	s.sleep_toggle()
	check(not s.pets[0].sleeping, "waking restores normal animation state")
	var before: Dictionary = s.export_state()
	s.paused = true
	s.tick(90)
	check(s.export_state() == before, "pause freezes all simulation clocks and needs")
	check(not s.feed() and not s.collect("brain"), "pause blocks gameplay mutation")
	s.paused = false
	var restored = Model.new()
	check(restored.import_state(before) and restored.export_state() == before, "save roundtrip restores complete simulation")
	check(restored.import_state(JSON.parse_string(JSON.stringify(before))), "serialized JSON save accepts browser numeric types")
	check(not restored.import_state({"version": 1, "pets": [{"id": 9}]}), "malformed save is rejected")
	var a = Art.new()
	check(a.textures.size() == 24, "all 24 original assets are loaded")
	check(a.anchor(s.pets[0]) == Vector2(112, 42), "heart reference anchor is fixed at 112,42")
	var temp: Dictionary = s.make_pet(2)
	check(a.anchor(temp) == Vector2(8, 48), "newborn slot does not overlap first resident")
	temp.organ = "brain"
	check(a.anchor(temp) == Vector2(112, 42), "brain reference anchor is fixed at 112,42")
	temp = s.make_pet(3)
	temp.organ = "gut"
	check(a.anchor(temp) == Vector2(112, 78), "gut reference anchor is fixed at 112,78")
	check(a.frame_offset(temp, 0).y + 84 == a.frame_offset(temp, 1).y + 96, "awake frames have identical ground baseline and scale")
	# Exact birth timers, cap includes the incubating egg.
	s = Model.new()
	s.tick(49.9)
	check(s.egg_left < 0, "no egg before 50 seconds")
	s.food = 3
	s.feed()
	s.tick(0.1)
	check(is_equal_approx(s.egg_left, 20), "egg appears at 50 seconds with full 20 seconds incubation")
	s.tick(19.9)
	check(s.pets.size() == 1, "no hatch before 20 seconds")
	s.tick(0.1)
	check(s.pets.size() == 2 and s.egg_left < 0 and s.pets[1].organ == "heart", "hatch at 20 seconds produces second resident in heart")
	s.select_pet(1)
	check(s.relocate() and s.pets[1].organ == "brain", "manual relocation of second resident to brain")
	check(not s.relocate(), "relocation cannot duplicate a resident")
	s.select_pet(0)
	check(not s.relocate(), "first resident stays in heart")
	# Keep the family healthy with the actual food economy, without injecting food.
	s = Model.new()
	var events: Array[Dictionary] = []
	var event_callback := func(kind: String):
		if kind in ["egg", "hatch", "win"]:
			events.append({"kind": kind, "at": s.elapsed, "final": s.final_left})
	s.event.connect(event_callback)
	for step in range(1610):
		care(s)
		s.tick(0.1)
		if not s.result.is_empty():
			break
	check(s.pets.size() == 3, "only three residents are produced")
	check(s.result == "win" and s.pets.all(func(p: Dictionary): return p.alive), "real food economy supports a full three-resident win")
	var hatches: Array = events.filter(func(e: Dictionary): return e.kind == "hatch")
	var wins: Array = events.filter(func(e: Dictionary): return e.kind == "win")
	check(hatches.size() == 2 and absf(hatches[0].at - 70) < 0.11 and absf(hatches[1].at - 120) < 0.11, "hatches follow real 50/20 second schedule")
	check(wins.size() == 1 and absf(wins[0].at - hatches[1].at - 40) < 0.11, "final lasts exactly 40 seconds after third hatch")
	check(s.egg_left < 0, "no fourth resident or extra egg at cap")
	var stopped_at: float = s.elapsed
	s.tick(100)
	check(s.elapsed == stopped_at, "ending is stable and stops further simulation")
	s.event.disconnect(event_callback)
	var death = Model.new()
	death.set_view("human")
	death.tick(210)
	check(death.result == "loss" and not death.pets[0].alive, "neglect causes starvation even on human screen")
	var unhealthy = Model.new()
	unhealthy.pets[0].hunger = 100
	unhealthy.pets[0].joy = 0
	unhealthy.pets[0].energy = 0
	unhealthy.tick(50)
	check(unhealthy.egg_left > 19.9, "energy and joy do not block a well-fed parent")
	test_rebirth()
	print("RESULT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func care(s: RefCounted) -> void:
	for organ in ["brain", "gut"]:
		if s.available_food[organ]:
			s.collect(organ)
	for i in range(s.pets.size()):
		if not s.pets[i].alive:
			continue
		s.select_pet(i)
		if s.pets[i].hunger < 65 and s.food >= 3:
			s.feed()
		if s.pets[i].energy < 65 and not s.pets[i].sleeping:
			s.sleep_toggle()
		if s.pets[i].energy > 95 and s.pets[i].sleeping:
			s.sleep_toggle()
		if i > 0 and s.pets[i].organ == "heart":
			s.relocate()
		s.set_view("human")

func test_rebirth() -> void:
	var s = Model.new()
	s.reproduction_clock = 50
	s.pets[0].hunger = 70.0 + Model.HUNGER_DRAIN * 0.1
	s.tick(0.1)
	check(is_equal_approx(s.pets[0].hunger, 70.0) and s.egg_left < 0, "exactly 70 percent at the eligibility check blocks reproduction")
	s.pets[0].hunger = 71
	s.pets[0].energy = 0
	s.pets[0].joy = 0
	s.tick(0.01)
	check(s.egg_left == 20 and s.egg_slot == 2, "strictly above 70 reserves brain role regardless of energy and joy")
	s.tick(19.9)
	check(s.live_count() == 1, "reserved replacement cannot hatch early")
	s.tick(0.1)
	check(s.live_count() == 2 and s.pets[1].id == 2, "egg hatches into its stable role at twenty seconds")
	s.select_pet(1)
	check(s.relocate() and s.pets[1].organ == "brain", "brain role can be relocated")
	s.pets.append(s.make_pet(3))
	s.selected = 2
	s.relocate()
	s.pets[0].hunger = 90
	s.pets[1].hunger = 90
	s.pets[2].hunger = 90
	s.pets[0].energy = 85
	s.pets[0].joy = 85
	s.tick(0.01)
	check(s.final_left == 40, "three live residents start full forty-second final")
	var before := [float(s.pets[0].hunger), float(s.pets[1].hunger), float(s.pets[2].hunger)]
	s.tick(1)
	var parent_loss: float = before[0] - s.pets[0].hunger
	check(absf(parent_loss - 0.8064) < 0.00001, "Puh retains original three-resident hunger rate")
	check(absf((before[1] - s.pets[1].hunger) / parent_loss - 1.3) < 0.00001 and absf((before[2] - s.pets[2].hunger) / parent_loss - 1.3) < 0.00001, "both juniors drain exactly thirty percent faster")
	s.pets[1].hunger = 0
	s.pets[1].health = 6
	var dead_ref: Dictionary = s.pets[1]
	s.select_pet(1)
	s.tick(1)
	check(not s.pets[1].alive and s.pets[1].health == 0 and s.live_count() == 2, "starving junior dies and frees one live slot")
	check(s.result.is_empty() and s.final_left == -1 and s.selected == 0, "junior death resets final without a losing ending")
	var frozen: Dictionary = dead_ref.duplicate(true)
	s.tick(1)
	check(dead_ref == frozen, "dead resident no longer ages or updates any needs")
	s.select_pet(1)
	check(s.selected == 0, "dead resident cannot be selected")
	s.reproduction_clock = 49
	s.pets[0].hunger = 90
	s.tick(0.9)
	check(s.egg_left < 0, "replacement respects remaining reproduction cooldown")
	s.tick(0.1)
	check(s.egg_slot == 2 and s.egg_left == 20, "Puh reserves the vacated brain role after fifty seconds")
	var pending = Model.new()
	check(pending.import_state(s.export_state()) and pending.egg_slot == 2 and pending.live_count() == 2, "save restores dead role and pending replacement egg")
	for i in range(200):
		care(s)
		s.tick(0.1)
	check(s.live_count() == 3 and s.pets[1].organ == "heart" and s.pets[1].age < 0.11, "replacement has fresh independent state and is born in heart")
	check(s.pets[1] != frozen and dead_ref == frozen, "replacement never reuses dead resident state")
	check(absf(s.final_left - 40) < 0.01, "recovered trio restarts final from forty")
	s.select_pet(1)
	check(s.relocate() and s.pets[1].organ == "brain", "replacement returns to the freed brain")
	# Both junior roles can be lost, frozen and restored sequentially.
	s.pets[1].health = 0
	s.pets[2].health = 0
	s.tick(0.01)
	check(s.live_count() == 1 and s.final_left == -1 and s.result.is_empty(), "losing both juniors leaves Puh and a continuing game")
	var hatches: Array[int] = []
	var last_count := 1
	for i in range(1400):
		care(s)
		s.tick(0.1)
		var count: int = s.live_count()
		if count > last_count:
			hatches.append(s.pets.filter(func(p: Dictionary): return p.alive and p.age < 0.11)[0].id)
		last_count = count
		if count == 3:
			break
	check(hatches == [2, 3] and s.live_count() == 3, "both missing roles are restored sequentially with correct sprites")
	check(s.live_count() + (1 if s.egg_left >= 0 else 0) <= 3, "alive residents plus eggs never exceed three")
	for i in range(405):
		care(s)
		s.tick(0.1)
	check(s.result == "win", "restored trio can reach the original good ending")
	# Feeding stops starvation damage for the selected resident only.
	s = Model.new()
	s.pets[0].hunger = 0
	s.pets[0].health = 80
	s.tick(1)
	check(absf(s.pets[0].health - 74) < 0.001, "zero hunger gradually drains health")
	s.feed()
	s.tick(1)
	check(s.pets[0].health >= 74, "feeding stops health loss from starvation")
	s.pets[0].hunger = 1
	s.pets[0].health = 80
	s.tick(1)
	check(s.pets[0].hunger > 0 and s.pets[0].health == 80, "positive hunger never inflicts starvation damage")
	# Each collection owns a full interval, even near an old global boundary.
	s = Model.new()
	s.tick(6.99)
	s.collect("gut")
	s.tick(0.02)
	check(not s.available_food.gut and s.food_remaining("gut") > 6.9, "gut cannot immediately respawn at an unrelated global cycle boundary")
	s.tick(6.97)
	check(not s.available_food.gut, "gut waits a full seven seconds after collection")
	s.tick(0.01)
	check(s.available_food.gut and s.collect("gut") and not s.collect("gut"), "gut refills exactly one collectible after its own seven-second interval")
	# The previous on-disk format is accepted, without the removed need.
	var old: Dictionary = s.export_state()
	old.version = 1
	old.food_clock = 2.0
	old.erase("food_cooldowns")
	old.erase("egg_slot")
	old.pets[0]["clean"] = 0.0
	var migrated = Model.new()
	check(migrated.import_state(old) and not migrated.pets[0].has("clean") and absf(migrated.food_remaining("gut") - 5.0) < 0.001, "legacy save migrates needs and food timer without resetting progress")
	s = Model.new()
	s.pets.append(s.make_pet(2))
	s.pets.append(s.make_pet(3))
	s.pets[1].organ = "brain"
	s.pets[2].organ = "gut"
	s.reproduction_clock = 50
	s.pets[2].health = 0
	s.tick(0.01)
	check(s.pets[1].alive and not s.pets[2].alive and s.egg_slot == 3, "losing only the gut resident reserves gut, never the occupied brain")
	var saved_pending: Dictionary = s.export_state()
	s.paused = true
	s.tick(30)
	check(s.export_state() == saved_pending, "pause freezes a replacement egg, all needs and per-organ food cooldowns")
	s.paused = false
	var resumed = Model.new()
	check(resumed.import_state(JSON.parse_string(JSON.stringify(saved_pending))) and resumed.egg_slot == 3 and not resumed.pets[2].alive, "browser-format save preserves a pending gut replacement and dead slot")
	for i in range(200):
		care(resumed)
		resumed.tick(0.1)
	resumed.select_pet(2)
	check(resumed.live_count() == 3 and resumed.pets[2].organ == "heart" and resumed.relocate() and resumed.pets[2].organ == "gut", "single gut replacement is fresh, green-role and manually returns to gut")
	saved_pending.version = 1
	saved_pending.food_clock = 2.0
	saved_pending.result = "loss"
	saved_pending.erase("food_cooldowns")
	saved_pending.erase("egg_slot")
	var old_recovery = Model.new()
	check(old_recovery.import_state(JSON.parse_string(JSON.stringify(saved_pending))) and old_recovery.result.is_empty() and old_recovery.egg_slot == 3, "legacy junior-loss save resumes with correct replacement role instead of a permanent defeat")
