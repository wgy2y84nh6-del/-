class_name ParasiteGame
extends RefCounted
## Simulation only. Screens and animation never own or reset game state.

signal event(kind: String)

const EGG_INTERVAL := 50.0
const HATCH_TIME := 20.0
const FINAL_TIME := 40.0
const FOOD_CYCLE := 7.0
const HUNGER_DRAIN := 1.372
const JUNIOR_HUNGER_MULTIPLIER := 1.30
const MAX_PARASITES := 3
const SAVE_VERSION := 2

var pets: Array[Dictionary] = []
var food := 6
var available_food := {"brain": true, "gut": true}
var food_cooldowns := {"brain": 0.0, "gut": 0.0}
var reproduction_clock := 0.0
var egg_left := -1.0
var egg_slot := 0 # Reserved role: 2 = brain, 3 = gut. Dead roles can be reused.
var final_left := -1.0
var elapsed := 0.0
var result := ""
var selected := 0
var view := "heart"
var petting := false
var paused := false
var notice := "Пух уже дома. Собирай еду в мозгу и кишечнике."

func _init() -> void:
	pets.append(make_pet(1))

func make_pet(id: int) -> Dictionary:
	return {"id": id, "name": ["Пух", "Лилу", "Ростик"][id - 1],
		"organ": "heart", "hunger": 85.0,
		"energy": 85.0, "joy": 85.0, "health": 100.0,
		"sleeping": false, "alive": true, "age": 0.0}

func live_count() -> int:
	var count := 0
	for p in pets:
		if p.alive:
			count += 1
	return count

func vacant_slot() -> int:
	for id in range(2, MAX_PARASITES + 1):
		if id > pets.size() or not pets[id - 1].alive:
			return id
	return 0

func food_remaining(organ: String) -> float:
	return float(food_cooldowns.get(organ, 0.0))

func tick(delta: float) -> void:
	if paused or not result.is_empty() or delta <= 0.0:
		return
	# Substeps make starvation, eggs and the final independent of frame rate.
	var remaining := delta
	while remaining > 0.00001 and result.is_empty():
		var step := minf(remaining, 0.1)
		advance(step)
		remaining -= step

func advance(dt: float) -> void:
	elapsed += dt
	# One authoritative slot and cooldown per organ, never recreated by a view.
	for organ in ["brain", "gut"]:
		if not available_food[organ]:
			food_cooldowns[organ] = maxf(0, food_cooldowns[organ] - dt)
			if food_cooldowns[organ] <= 0.00001:
				food_cooldowns[organ] = 0.0
				available_food[organ] = true
	# Keep elapsed time since the last lay even while the population is full.
	reproduction_clock = minf(EGG_INTERVAL, reproduction_clock + dt)
	var pressure := 1.0 + 0.22 * (live_count() - 1)
	for i in range(pets.size()):
		var p: Dictionary = pets[i]
		if not p.alive:
			continue
		if p.health <= 0.00001:
			kill_pet(i)
			if not result.is_empty():
				return
			continue
		p.age += dt
		var hunger_multiplier := 1.0 if p.id == 1 else JUNIOR_HUNGER_MULTIPLIER
		p.hunger = maxf(0, p.hunger - HUNGER_DRAIN * pressure * hunger_multiplier * dt)
		p.joy = maxf(0, p.joy - 0.35 * pressure * dt)
		if p.sleeping:
			p.energy = minf(100, p.energy + 8.0 * dt)
		else:
			p.energy = maxf(0, p.energy - 0.42 * pressure * dt)
		if petting and i == selected and p.organ == view and not p.sleeping:
			p.joy = minf(100, p.joy + 18.0 * dt)
		var damage := 0.0
		if p.hunger <= 0:
			damage += 10.5
		if p.energy <= 0:
			damage += 0.5
		if p.joy <= 0:
			damage += 0.3
		p.health = clampf(p.health - damage * dt, 0, 100)
		if p.health <= 0.00001:
			kill_pet(i)
			if not result.is_empty():
				return
		elif damage == 0 and p.hunger > 35:
			p.health = minf(100, p.health + 0.4 * dt)
	# Existing final timer is advanced before a hatch can create a new one.
	if live_count() < MAX_PARASITES:
		final_left = -1.0
	elif final_left < 0:
		final_left = FINAL_TIME
	elif final_left >= 0:
		final_left = maxf(0, final_left - dt)
		if final_left <= 0.00001:
			result = "win"
			petting = false
			notice = "Человек умер. Все трое живы — теперь это ваш дом."
			event.emit("win")
			return
	if egg_left >= 0:
		egg_left = maxf(0, egg_left - dt)
		if egg_left <= 0.00001:
			var id := egg_slot
			egg_left = -1.0
			egg_slot = 0
			if id >= 2 and id <= MAX_PARASITES and live_count() < MAX_PARASITES:
				var newborn := make_pet(id)
				if id > pets.size():
					pets.append(newborn)
				else:
					pets[id - 1] = newborn
				notice = "%s вылупился в сердце! Выбери его и нажми «Переселить»." % newborn.name
				if live_count() == MAX_PARASITES:
					final_left = FINAL_TIME
				event.emit("hatch")
	if live_count() < MAX_PARASITES:
		var parent: Dictionary = pets[0]
		var healthy: bool = parent.alive and parent.hunger > 70.0
		if reproduction_clock + 0.00001 >= EGG_INTERVAL and egg_left < 0 and healthy:
			egg_slot = vacant_slot()
			egg_left = HATCH_TIME
			reproduction_clock = 0.0
			notice = "Пух отложил яйцо. До вылупления — 20 секунд."
			event.emit("egg")

func kill_pet(index: int) -> void:
	var p: Dictionary = pets[index]
	p.alive = false
	p.health = 0.0
	p.sleeping = false
	final_left = -1.0
	if selected == index:
		petting = false
		selected = 0
	if p.id == 1:
		result = "loss"
		petting = false
		notice = "Пух погиб. В следующий раз не оставляй его голодным."
		event.emit("loss")
	else:
		notice = "%s погиб. Пух может вырастить ему замену." % p.name
		event.emit("death")

func collect(organ: String) -> bool:
	if paused or not result.is_empty() or not available_food.get(organ, false):
		return false
	available_food[organ] = false
	food_cooldowns[organ] = FOOD_CYCLE
	food += 1
	notice = "+1 еда. Для одного кормления нужно 3."
	event.emit("collect")
	return true

func feed() -> bool:
	if not can_care():
		return false
	if food < 3:
		notice = "Нужно 3 еды. Собирай шарики в мозгу и кишечнике."
		return false
	food -= 3
	pets[selected].hunger = minf(100, pets[selected].hunger + 42)
	notice = "%s сыт. −3 еды." % pets[selected].name
	event.emit("feed")
	return true

func sleep_toggle() -> bool:
	if not can_care():
		return false
	petting = false
	pets[selected].sleeping = not pets[selected].sleeping
	notice = "%s %s." % [pets[selected].name, "спит и восстанавливает энергию" if pets[selected].sleeping else "проснулся"]
	event.emit("sleep")
	return true

func start_petting() -> bool:
	if not can_care():
		return false
	if pets[selected].organ != view:
		notice = "Нажми «К питомцу», чтобы погладить его дома."
		return false
	if pets[selected].sleeping:
		notice = "Сначала разбуди питомца."
		return false
	petting = true
	event.emit("pet")
	return true

func can_care() -> bool:
	return not paused and result.is_empty() and selected >= 0 and selected < pets.size() and pets[selected].alive

func set_view(destination: String) -> void:
	if destination in ["human", "heart", "brain", "gut"]:
		petting = false
		view = destination

func select_pet(index: int) -> void:
	if index >= 0 and index < pets.size() and pets[index].alive:
		petting = false
		selected = index

func relocate() -> bool:
	if not can_care():
		return false
	var p: Dictionary = pets[selected]
	if p.id == 1:
		notice = "Сердце — дом Пуха. Переселяются только Лилу и Ростик."
		return false
	var target: String = "brain" if p.id == 2 else "gut"
	if p.organ == target:
		notice = "%s уже дома." % p.name
		return false
	petting = false
	p.organ = target
	view = target
	notice = "%s теперь живёт %s." % [p.name, "в мозгу" if target == "brain" else "в кишечнике"]
	event.emit("move")
	return true

func export_state() -> Dictionary:
	return {"version": SAVE_VERSION, "pets": pets.duplicate(true), "food": food,
		"available_food": available_food.duplicate(), "food_cooldowns": food_cooldowns.duplicate(),
		"reproduction_clock": reproduction_clock, "egg_left": egg_left,
		"egg_slot": egg_slot, "live_count": live_count(),
		"final_left": final_left, "elapsed": elapsed, "result": result,
		"selected": selected, "view": view, "notice": notice}

func import_state(data: Dictionary) -> bool:
	if data.get("version") != 1 and data.get("version") != SAVE_VERSION:
		return false
	var loaded_pets = data.get("pets", [])
	if not loaded_pets is Array or loaded_pets.size() < 1 or loaded_pets.size() > 3:
		return false
	var normalized: Array[Dictionary] = []
	for i in range(loaded_pets.size()):
		var p = loaded_pets[i]
		if not p is Dictionary or int(p.get("id", 0)) != i + 1:
			return false
		for key in ["hunger", "energy", "joy", "health", "age"]:
			if not valid_number(p.get(key)):
				return false
		if p.get("organ", "") not in ["heart", "brain", "gut"] or not p.get("name") is String:
			return false
		if not p.get("sleeping") is bool or not p.get("alive") is bool:
			return false
		# Only current fields survive migration; obsolete needs are discarded.
		var current := make_pet(i + 1)
		for key in current:
			current[key] = p[key]
		for key in ["hunger", "energy", "joy", "health"]:
			current[key] = clampf(float(current[key]), 0, 100)
		current.age = maxf(0, float(current.age))
		current.alive = current.alive and current.health > 0
		normalized.append(current)
	var loaded_food = data.get("available_food", {})
	if not loaded_food is Dictionary or not loaded_food.get("brain") is bool or not loaded_food.get("gut") is bool:
		return false
	for key in ["reproduction_clock", "egg_left", "final_left", "elapsed", "food", "selected"]:
		if not valid_number(data.get(key)):
			return false
	if data.get("view") not in ["human", "heart", "brain", "gut"] or data.get("result") not in ["", "win", "loss"]:
		return false
	var loaded_cooldowns: Dictionary = {}
	if data.version == 1:
		if not valid_number(data.get("food_clock")):
			return false
		for organ in ["brain", "gut"]:
			loaded_cooldowns[organ] = 0.0 if loaded_food[organ] else clampf(FOOD_CYCLE - data.food_clock, 0, FOOD_CYCLE)
	else:
		if not data.get("food_cooldowns") is Dictionary or not valid_number(data.get("egg_slot")):
			return false
		for organ in ["brain", "gut"]:
			if not valid_number(data.food_cooldowns.get(organ)):
				return false
			loaded_cooldowns[organ] = 0.0 if loaded_food[organ] else clampf(data.food_cooldowns[organ], 0, FOOD_CYCLE)
	var reserved := int(data.get("egg_slot", 0))
	if data.egg_left >= 0:
		if data.version == 1:
			for id in range(2, MAX_PARASITES + 1):
				if id > normalized.size() or not normalized[id - 1].alive:
					reserved = id
					break
		if reserved < 2 or reserved > MAX_PARASITES or reserved > normalized.size() + 1:
			return false
		if reserved <= normalized.size() and normalized[reserved - 1].alive:
			return false
	else:
		reserved = 0
	pets.clear()
	pets.assign(normalized)
	food = maxi(0, int(data.food))
	available_food = {"brain": loaded_food.brain, "gut": loaded_food.gut}
	food_cooldowns = loaded_cooldowns
	reproduction_clock = clampf(float(data.reproduction_clock), 0, EGG_INTERVAL)
	egg_left = clampf(float(data.egg_left), -1, HATCH_TIME)
	egg_slot = reserved
	final_left = clampf(float(data.final_left), -1, FINAL_TIME)
	elapsed = maxf(0, float(data.elapsed))
	result = data.result
	if not pets[0].alive:
		result = "loss"
	elif result == "loss" or result == "win" and live_count() < MAX_PARASITES:
		result = "" # A junior death in an older save is now recoverable.
	if live_count() < MAX_PARASITES:
		final_left = -1.0
	selected = clampi(int(data.selected), 0, pets.size() - 1)
	if not pets[selected].alive:
		selected = 0
	view = data.view
	notice = str(data.get("notice", "С возвращением домой."))
	paused = false
	petting = false
	return true

func valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

