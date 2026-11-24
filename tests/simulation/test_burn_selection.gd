extends SceneTree

class World extends "res://scripts/main.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass

class Enemy extends CharacterBody3D:
	var health := {"dead":false}
	var burning := false
	var full := false
	func set_burning(on: bool, detailed := true) -> void:
		burning = on
		full = on and detailed
	func burn_flicker(_now: float) -> void: pass

class Quality extends Node3D:
	var embers_full := 6

func _initialize() -> void: run.call_deferred()

# Previous production algorithm, retained only for behavior and timing comparison.
func legacy(c: Node3D, now: float) -> void:
	var lit: Array = []
	for id in c.enemies:
		var e: CharacterBody3D = c.enemies[id]
		if e.visible and not e.health.dead and c.effects.has(id,"Burn",now): lit.append(e)
		else: e.set_burning(false)
	var camera := c.get_viewport().get_camera_3d()
	var eye: Vector3 = camera.global_position if camera else c.player.global_position
	if lit.size() > c.vfx.embers_full:
		lit.sort_custom(func(a,b): return eye.distance_squared_to(a.global_position) < eye.distance_squared_to(b.global_position))
	for i in lit.size():
		lit[i].set_burning(true,i<c.vfx.embers_full)
		lit[i].burn_flicker(now)

func state(c: Node3D) -> Array:
	return c.enemies.values().map(func(e): return [e.burning,e.full])

func run() -> void:
	var c := World.new()
	root.add_child(c)
	c.player = CharacterBody3D.new()
	c.add_child(c.player)
	c.vfx = Quality.new()
	c.add_child(c.vfx)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in 250:
		var e := Enemy.new()
		c.add_child(e)
		e.position = Vector3(rng.randf_range(-30,30),0,rng.randf_range(-30,30))
		c.enemies[str(i)] = e
		c.effects.apply(str(i),"Burn",10.0,0.0)
	var checks := 0
	for cap in [0,1,6,250,300]:
		c.vfx.embers_full = cap
		for focus in [Vector3.ZERO,Vector3(20,1,20)]:
			c.player.position = focus
			legacy(c,1.0)
			var expected := state(c)
			c._show_burning(1.0)
			assert(state(c) == expected,"nearest selection must match")
			checks += 1
	var camera := Camera3D.new()
	c.add_child(camera)
	camera.current = true
	camera.position = Vector3(-20,2,-20)
	c.vfx.embers_full = 6
	for ties in [false,true]:
		if ties:
			for i in 8: c.enemies[str(i)].position = camera.position
		legacy(c,1.0)
		var expected := state(c)
		c._show_burning(1.0)
		assert(state(c) == expected,"camera focus and equal distances must match")
		checks += 1
	c.enemies["0"].health.dead = true
	c.enemies["1"].hide()
	for now in [1.0,11.0]:
		legacy(c,now)
		var expected := state(c)
		c._show_burning(now)
		assert(state(c) == expected,"dead, hidden and expired effects must clear")
		checks += 1
	c.enemies["0"].health.dead = false
	c.enemies["1"].show()
	c.vfx.embers_full = 6
	var old_us := 0
	var new_us := 0
	for trial in 6:
		for mode in ([0,1] if trial%2==0 else [1,0]):
			var start := Time.get_ticks_usec()
			for i in 300:
				if mode==0: legacy(c,1.0)
				else: c._show_burning(1.0)
			if mode==0: old_us += Time.get_ticks_usec()-start
			else: new_us += Time.get_ticks_usec()-start
	print("BURN_SELECTION ",JSON.stringify({"checks":checks,"legacy_us":old_us,"current_us":new_us,"ratio":float(new_us)/old_us}))
	c.free()
	quit(0 if new_us < old_us*0.85 else 1)
