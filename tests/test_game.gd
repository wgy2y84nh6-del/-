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
	s.tick(5.9)
	check(not s.available_food.brain, "no early respawn")
	s.tick(0.1)
	check(s.available_food.brain, "respawn at next six-second cycle")
	s.tick(18)
	check(s.collect("gut") and not s.collect("gut"), "missed cycles do not stack food")
	food = s.food
	s.pets[0].hunger = 20
	check(s.feed() and s.food == food - 3 and s.pets[0].hunger == 62, "feeding costs three and restores hunger")
	s.food = 2
	check(not s.feed() and s.food == 2, "insufficient food cannot be consumed")
	s.pets[0].clean = 10
	s.wash()
	check(s.pets[0].clean == 55 and s.pets[0].hunger == 62, "wash changes cleanliness independently")
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
	check(not s.feed() and not s.wash() and not s.collect("brain"), "pause blocks gameplay mutation")
	s.paused = false
	var restored = Model.new()
	check(restored.import_state(before) and restored.export_state() == before, "save roundtrip restores complete simulation")
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
	unhealthy.pets[0].joy = 10
	unhealthy.tick(50)
	check(unhealthy.egg_left < 0, "unhappy parent cannot reproduce")
	print("RESULT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func care(s: RefCounted) -> void:
	for organ in ["brain", "gut"]:
		if s.available_food[organ]:
			s.collect(organ)
	for i in range(s.pets.size()):
		s.select_pet(i)
		if s.pets[i].hunger < 65 and s.food >= 3:
			s.feed()
		if s.pets[i].clean < 65:
			s.wash()
		if s.pets[i].energy < 65 and not s.pets[i].sleeping:
			s.sleep_toggle()
		if s.pets[i].energy > 95 and s.pets[i].sleeping:
			s.sleep_toggle()
		if i > 0 and s.pets[i].organ == "heart":
			s.relocate()
		s.set_view("human")
