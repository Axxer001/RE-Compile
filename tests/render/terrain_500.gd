extends "res://tests/render/run_render.gd"

func run(c: Node3D) -> void:
	c.park_enemies()
	await frame()
	var previous: Image
	for spec in [["camp",Vector2(75,134),0.0],["hill",Vector2(180,105),90.0],["south",Vector2(165,215),0.0]]:
		var p: Vector2 = spec[1]
		place(c,Vector3(p.x,c.map.terrain.height_at(p)+0.1,p.y),spec[2])
		await frame()
		var img := shot("terrain-"+spec[0]+".png")
		check(luma(img,0.8)>0.005,"terrain view is visible: "+spec[0])
		if previous: check(distinct(previous,img),"expanded regions have distinct views")
		previous = img
		var trees := c.find_child("KitTrees",true,false)
		if trees and trees.has_method("refresh"):
			for i in 120:
				await frame()
				if trees.pending.is_empty() and trees.last_focus.distance_to(p) < 3.0: break
			check(trees.last_focus.distance_to(p) < 3.0,"tree streaming follows the real camera: "+spec[0])
			check(trees.pending.is_empty() and trees.loaded.size() > 0 and trees.loaded.size() < 450,"tree details settle with a bounded cache: "+spec[0])
			shot("terrain-"+spec[0]+"-settled.png")
	finish()
