class_name ParasiteGame
extends RefCounted
## Simulation only. Screens and animation never own or reset game state.

signal event(kind: String)

const EGG_INTERVAL := 50.0
const HATCH_TIME := 20.0
const FINAL_TIME := 40.0
const FOOD_CYCLE := 6.0
const MAX_PARASITES := 3
const SAVE_VERSION := 1

var pets: Array[Dictionary] = []
var food := 6
var available_food := {"brain": true, "gut": true}
var food_clock := 0.0
var reproduction_clock := 0.0
var egg_left := -1.0
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
		"organ": "heart", "hunger": 85.0, "clean": 85.0,
		"energy": 85.0, "joy": 85.0, "health": 100.0,
		"sleeping": false, "alive": true, "age": 0.0}

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
	food_clock += dt
	if food_clock + 0.00001 >= FOOD_CYCLE:
		food_clock = fmod(food_clock + 0.00001, FOOD_CYCLE)
		# A boolean slot per organ: missed cycles never stack food.
		available_food["brain"] = true
		available_food["gut"] = true
	var pressure := 1.0 + 0.22 * (pets.size() - 1)
	for i in range(pets.size()):
		var p: Dictionary = pets[i]
		if not p.alive:
			continue
		p.age += dt
		p.hunger = maxf(0, p.hunger - 0.5 * pressure * dt)
		p.clean = maxf(0, p.clean - 0.15 * pressure * dt)
		p.joy = maxf(0, p.joy - 0.20 * pressure * dt)
		if p.sleeping:
			p.energy = minf(100, p.energy + 8.0 * dt)
		else:
			p.energy = maxf(0, p.energy - 0.24 * pressure * dt)
		if petting and i == selected and p.organ == view and not p.sleeping:
			p.joy = minf(100, p.joy + 18.0 * dt)
		var damage := 0.0
		if p.hunger <= 0:
			damage += 6.0
		if p.clean <= 0:
			damage += 0.7
		if p.energy <= 0:
			damage += 0.5
		if p.joy <= 0:
			damage += 0.3
		p.health = clampf(p.health - damage * dt, 0, 100)
		if damage == 0 and minf(p.hunger, p.clean) > 35:
			p.health = minf(100, p.health + 0.4 * dt)
		if p.health <= 0:
			p.alive = false
			result = "loss"
			petting = false
			notice = "%s погиб. В следующий раз не оставляй его голодным." % p.name
			event.emit("loss")
			return
	# Existing final timer is advanced before a hatch can create a new one.
	if final_left >= 0:
		final_left = maxf(0, final_left - dt)
		if final_left <= 0.00001 and pets.size() == MAX_PARASITES:
			result = "win"
			petting = false
			notice = "Человек умер. Все трое живы — теперь это ваш дом."
			event.emit("win")
			return
	if egg_left >= 0:
		egg_left = maxf(0, egg_left - dt)
		if egg_left <= 0.00001:
			egg_left = -1.0
			if pets.size() < MAX_PARASITES:
				pets.append(make_pet(pets.size() + 1))
				var newborn: Dictionary = pets.back()
				notice = "%s вылупился в сердце! Выбери его и нажми «Переселить»." % newborn.name
				if pets.size() == MAX_PARASITES:
					final_left = FINAL_TIME
				event.emit("hatch")
	if pets.size() < MAX_PARASITES:
		reproduction_clock = minf(EGG_INTERVAL, reproduction_clock + dt)
		var parent: Dictionary = pets[0]
		var healthy: bool = parent.alive and minf(parent.hunger, parent.clean) >= 50.0 and minf(parent.energy, parent.joy) >= 50.0
		if reproduction_clock + 0.00001 >= EGG_INTERVAL and egg_left < 0 and healthy:
			egg_left = HATCH_TIME
			reproduction_clock = 0.0
			notice = "Пух отложил яйцо. До вылупления — 20 секунд."
			event.emit("egg")

func collect(organ: String) -> bool:
	if paused or not result.is_empty() or not available_food.get(organ, false):
		return false
	available_food[organ] = false
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

func wash() -> bool:
	if not can_care():
		return false
	pets[selected].clean = minf(100, pets[selected].clean + 45)
	notice = "%s снова чист." % pets[selected].name
	event.emit("wash")
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
	if index >= 0 and index < pets.size():
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
		"available_food": available_food.duplicate(), "food_clock": food_clock,
		"reproduction_clock": reproduction_clock, "egg_left": egg_left,
		"final_left": final_left, "elapsed": elapsed, "result": result,
		"selected": selected, "view": view, "notice": notice}

func import_state(data: Dictionary) -> bool:
	if data.get("version") != SAVE_VERSION:
		return false
	var loaded_pets = data.get("pets", [])
	if not loaded_pets is Array or loaded_pets.size() < 1 or loaded_pets.size() > 3:
		return false
	for i in range(loaded_pets.size()):
		var p = loaded_pets[i]
		if not p is Dictionary or int(p.get("id", 0)) != i + 1:
			return false
		for key in ["hunger", "clean", "energy", "joy", "health", "age"]:
			if not p.get(key) is float and not p.get(key) is int:
				return false
		if p.get("organ", "") not in ["heart", "brain", "gut"] or not p.get("name") is String:
			return false
		if not p.get("sleeping") is bool or not p.get("alive") is bool:
			return false
	var loaded_food = data.get("available_food", {})
	if not loaded_food is Dictionary or not loaded_food.get("brain") is bool or not loaded_food.get("gut") is bool:
		return false
	for key in ["food_clock", "reproduction_clock", "egg_left", "final_left", "elapsed", "food", "selected"]:
		if not data.get(key) is float and not data.get(key) is int:
			return false
	if data.get("view") not in ["human", "heart", "brain", "gut"] or data.get("result") not in ["", "win", "loss"]:
		return false
	pets.clear()
	for p in loaded_pets:
		pets.append(p.duplicate(true))
	food = maxi(0, int(data.food))
	available_food = loaded_food.duplicate()
	food_clock = clampf(float(data.food_clock), 0, FOOD_CYCLE)
	reproduction_clock = clampf(float(data.reproduction_clock), 0, EGG_INTERVAL)
	egg_left = clampf(float(data.egg_left), -1, HATCH_TIME)
	final_left = clampf(float(data.final_left), -1, FINAL_TIME)
	elapsed = maxf(0, float(data.elapsed))
	result = data.result
	selected = clampi(int(data.selected), 0, pets.size() - 1)
	view = data.view
	notice = str(data.get("notice", "С возвращением домой."))
	paused = false
	petting = false
	return true

