package game

import sa "core:container/small_array"
import math "core:math"
import rl "vendor:raylib"

World :: struct {
	actors:  sa.Small_Array(8, Actor2D),
	solids:  sa.Small_Array(256, Solid2D),
	sensors: sa.Small_Array(128, Sensor2D),
}

world_push_actor :: proc(world: ^World, actor: Actor2D) {
	sa.push(&world.actors, actor)
}

world_push_solid :: proc(world: ^World, solid: Solid2D) {
	sa.push(&world.solids, solid)
}

World_Actor_Iterator :: struct {
	index: int,
	data:  []Actor2D,
}

world_make_actors_iterator :: proc(world: ^World) -> World_Actor_Iterator {
	return World_Actor_Iterator{data = sa.slice(&world.actors)}
}

world_actors_iter :: proc(it: ^World_Actor_Iterator) -> (val: Actor2D, idx: int, cond: bool) {
	if it.index >= len(it.data) {
		return Actor2D{}, 0, false
	}

	it.index += 1
	return it.data[it.index], it.index, true
}

World_Solid_Iterator :: struct {
	index: int,
	data:  []Solid2D,
}

world_make_solids_iterator :: proc(world: ^World) -> World_Solid_Iterator {
	return World_Solid_Iterator{data = sa.slice(&world.solids)}
}

world_solids_iter :: proc(it: ^World_Solid_Iterator) -> (val: Solid2D, idx: int, cond: bool) {
	if it.index >= len(it.data) {
		return Solid2D{}, 0, false
	}

	val = it.data[it.index]
	idx = it.index
	cond = it.index < len(it.data)
	it.index += 1
	return
}


CollisionBox2D :: struct {
	size: rl.Vector2,
}

collision_box_rect :: proc(position: rl.Vector2, box: CollisionBox2D) -> rl.Rectangle {
	return rl.Rectangle{x = position.x, y = position.y, width = box.size.x, height = box.size.y}
}

Actor2D :: struct {
	position:       rl.Vector2,
	remainder:      rl.Vector2,
	collision_box:  CollisionBox2D,

	// if true, the actor will ignore solids
	non_collidable: bool,
}

SolidCollisionInfo :: struct {
	solid:     Solid2D,
	direction: rl.Vector2,
}

SensorCollisionInfo :: struct {
	sensor:    Sensor2D,
	direction: rl.Vector2,
}

NoCollision :: struct {}

CollisionInfo :: union {
	NoCollision,
	SolidCollisionInfo,
	SensorCollisionInfo,
}

collision_info_stops_movement :: proc(cinfo: CollisionInfo) -> bool {
	switch v in cinfo {
	case NoCollision:
		return false
	case SensorCollisionInfo:
		return false
	case SolidCollisionInfo:
		return true
	case:
		return false
	}
}

actor_move_x :: proc(actor: ^Actor2D, world: ^World, amount: f32) -> CollisionInfo {
	actor.remainder.x += amount

	move_pixels := math.round(actor.remainder.x)
	if move_pixels == 0 {
		return nil
	}

	actor.remainder.x -= f32(move_pixels)

	sign := math.sign(move_pixels)
	move_pixels_int := int(move_pixels)
	for _ in 0 ..< abs(move_pixels_int) {
		if actor.non_collidable {
			actor.position.x += sign
			continue
		}

		cinfo := actor_check_collision(actor, sa.slice(&world.solids), f32(sign), 0.0)
		if collision_info_stops_movement(cinfo) {
			return cinfo
		}

		actor.position.x += sign
	}

	return nil
}

actor_move_y :: proc(actor: ^Actor2D, world: ^World, amount: f32) -> CollisionInfo {
	actor.remainder.y += amount
	move_pixels := math.round(actor.remainder.y)
	if move_pixels == 0 {
		return nil
	}

	actor.remainder.y -= f32(move_pixels)

	sign := math.sign(move_pixels)
	move_pixels_int := int(move_pixels)
	for _ in 0 ..< abs(move_pixels_int) {
		// move like there is no tomorrow!
		if actor.non_collidable {
			actor.position.y += sign
			continue
		}

		cinfo := actor_check_collision(actor, sa.slice(&world.solids), 0.0, f32(sign))
		if collision_info_stops_movement(cinfo) {
			return cinfo
		}

		actor.position.y += sign
	}

	return nil
}

actor_solid_check_collision :: proc(
	actor: ^Actor2D,
	solids: []Solid2D,
	dx: f32,
	dy: f32,
) -> CollisionInfo {
	actor_future_rect := collision_box_rect(actor.position, actor.collision_box)
	actor_future_rect.x += dx
	actor_future_rect.y += dy

	for solid in solids {
		if !solid.collidable {
			continue
		}

		if rl.CheckCollisionRecs(
			actor_future_rect,
			collision_box_rect(solid.position, solid.collision_box),
		) {
			return SolidCollisionInfo{solid = solid, direction = {dx, dy}}
		}
	}

	return nil
}

// is_riding checks if the actor is riding a given solid
actor_is_riding :: proc(actor: ^Actor2D, solid: Solid2D) -> bool {
	solid_rect := collision_box_rect(solid.position, solid.collision_box)

	actor_feet_rect := collision_box_rect(actor.position, actor.collision_box)
	actor_feet_rect.y += 1.0

	return rl.CheckCollisionRecs(actor_feet_rect, solid_rect)
}

actor_is_on_floor :: proc(actor: ^Actor2D, world: ^World) -> bool {
	for solid in sa.slice(&world.solids) {
		if actor_is_riding(actor, solid) {
			return true
		}
	}
	return false
}

Solid2D :: struct {
	position:      rl.Vector2,
	collision_box: CollisionBox2D,
	remainder:     rl.Vector2,
	collidable:    bool,
}

// returns a list of actors riding a given solid
// uses the temp allocator to create a slice of all the riding actors
// caller has the responsibility of either clearing the temp_allocator,
// or of freeing the returned slice
get_actors_riding :: proc(
	solid: Solid2D,
	actors: []Actor2D,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	ret: []Actor2D,
) {
	ret = make([]Actor2D, len(actors), context.temp_allocator, loc)
	for &actor, i in actors {
		if actor_is_riding(&actor, solid) {
			ret[i] = actor
		}
	}
	return
}

contains :: proc(slice: []$T, value: T) -> bool {
	for &v in slice {
		if v == value {
			return true
		}
	}
	return false
}

solid_move_x :: proc(solid: ^Solid2D, world: ^World, amount: f32) {
	solid.remainder.x += amount

	move_x := math.round(solid.remainder.x)
	if move_x == 0 {
		return
	}

	solid.remainder.x -= f32(move_x)
	solid.position.x += f32(move_x)

	riding_actors := get_actors_riding(solid^, sa.slice(&world.actors))
	defer delete(riding_actors)

	solid.collidable = false
	defer {solid.collidable = true}

	if move_x > 0 {
		for &actor in sa.slice(&world.actors) {
			actor_current_rect := collision_box_rect(actor.position, actor.collision_box)
			solid_new_rect := collision_box_rect(solid.position, solid.collision_box)
			if rl.CheckCollisionRecs(actor_current_rect, solid_new_rect) {
				// overlap
				actor_move_x(&actor, world, solid.position.x - actor.position.x)
			} else if contains(riding_actors[:], actor) {
				// ride
				actor_move_x(&actor, world, move_x)
			}
		}
	} else {
		for &actor in sa.slice(&world.actors) {
			actor_current_rect := collision_box_rect(actor.position, actor.collision_box)
			solid_new_rect := collision_box_rect(solid.position, solid.collision_box)
			if rl.CheckCollisionRecs(actor_current_rect, solid_new_rect) {
				// overlap
				actor_move_x(&actor, world, actor.position.x - solid.position.x)
			} else if contains(riding_actors[:], actor) {
				// ride
				actor_move_x(&actor, world, move_x)
			}
		}
	}
}

solid_move_y :: proc(solid: ^Solid2D, world: ^World, amount: f32) {
	solid.remainder.y += amount

	move_y := math.round(solid.remainder.y)
	if move_y == 0 {
		return
	}

	solid.remainder.y -= f32(move_y)
	solid.position.y += f32(move_y)

	riding_actors := get_actors_riding(solid^, sa.slice(&world.actors))

	solid.collidable = false
	defer {solid.collidable = true}

	if move_y > 0 {
		for &actor in sa.slice(&world.actors) {
			actor_current_rect := collision_box_rect(actor.position, actor.collision_box)
			solid_new_rect := collision_box_rect(solid.position, solid.collision_box)
			if rl.CheckCollisionRecs(actor_current_rect, solid_new_rect) {
				// overlap
				actor_move_y(&actor, world, solid.position.y - actor.position.y)
			} else if contains(riding_actors[:], actor) {
				// ride
				actor_move_y(&actor, world, move_y)
			}
		}
	} else {
		for &actor in sa.slice(&world.actors) {
			actor_current_rect := collision_box_rect(actor.position, actor.collision_box)
			solid_new_rect := collision_box_rect(solid.position, solid.collision_box)
			if rl.CheckCollisionRecs(actor_current_rect, solid_new_rect) {
				// overlap
				actor_move_y(&actor, world, actor.position.y - solid.position.y)
			} else if contains(riding_actors[:], actor) {
				// ride
				actor_move_y(&actor, world, move_y)
			}
		}
	}
}

// kind of like a solid, but doesn't block movement
Sensor2D :: struct {
	position:      rl.Vector2,
	collision_box: CollisionBox2D,
}

actor_sensor_check_collision :: proc(
	actor: ^Actor2D,
	sensors: []Sensor2D,
	dx: f32,
	dy: f32,
) -> CollisionInfo {
	actor_future_rect := collision_box_rect(actor.position, actor.collision_box)
	actor_future_rect.x += dx
	actor_future_rect.y += dy

	for sensor in sensors {
		if rl.CheckCollisionRecs(
			actor_future_rect,
			collision_box_rect(sensor.position, sensor.collision_box),
		) {
			return SensorCollisionInfo{sensor = sensor, direction = {dx, dy}}
		}
	}

	return nil
}


actor_check_collision :: proc {
	actor_sensor_check_collision,
	actor_solid_check_collision,
}
