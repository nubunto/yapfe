package game

import "base:intrinsics"
import rl "vendor:raylib"
import math "core:math"

Character_Stats :: struct {
    ground_move_speed: f32,
    dash_speed: f32,
    horizontal_acceleration: f32,
    horizontal_deceleration: f32,
    horizontal_friction: f32,
    jump_force: f32,
    air_move_speed: f32,
    air_acceleration: f32,
    air_deceleration: f32,
    air_friction: f32,
    gravity: rl.Vector2,
    max_fall_speed: f32,
}

Current_Stats :: struct {
    max_h_speed: f32,
    h_accel: f32,
    h_friction: f32,
}

Character_Default_State :: union #no_nil {
    Character_State_Idle,
    Character_State_Walking,
    Character_State_Dash,
    // more to come!
}

Character_State_Idle :: struct {
}

Character_State_Walking :: struct {
    direction: i8,
}

Character_State_Dash :: struct {
    direction: i8,
}

Character :: struct {
    using actor: Actor2D,
    stats: Character_Stats,
    state: Character_Default_State,
    velocity: rl.Vector2,
    is_grounded: bool,
}

apply_gravity :: proc(character: ^Character, world: ^World) {
    if !actor_is_on_floor(&character.actor, world) {
        character.velocity.y += character.stats.gravity.y * rl.GetFrameTime()
    }
}

character_try_jump :: proc(character: ^Character, world: ^World) {
    if actor_is_on_floor(&character.actor, world) {
        character.velocity.y = -character.stats.jump_force
    }
}

character_idle_state :: proc(character: ^Character, world: ^World, input: rl.Vector2, stats: Current_Stats) {
    if input.x != 0 {
        if character.is_grounded {
            character.state = Character_State_Dash {
                direction = i8(math.sign(input.x)),
            }
        } else {
            character.state = Character_State_Walking {
                direction = i8(math.sign(input.x)),
            }
        }
    } else {
        character.velocity.x = move_towards(character.velocity.x, 0, stats.h_friction * rl.GetFrameTime())
    }

    apply_gravity(character, world)
}

character_walking_state :: proc(character: ^Character, world: ^World, input: rl.Vector2, stats: Current_Stats) {
    if input.x == 0 {
        character.state = Character_State_Idle{}
    }

    character.velocity.x = move_towards(character.velocity.x, input.x * stats.max_h_speed, stats.h_accel * rl.GetFrameTime())
    apply_gravity(character, world)
}

character_dash_state :: proc(character: ^Character, world: ^World, input: rl.Vector2, stats: Current_Stats) {
    if input.x == 0 {
        character.state = Character_State_Idle{}
        return
    }

    character.velocity.x = input.x * character.stats.dash_speed
    apply_gravity(character, world)
}

character_draw :: proc(character: Character) {
	// rl.DrawTextureEx(character.texture, character.actor.position, 0, 1, rl.WHITE)
	rl.DrawRectangleV(character.position, character.collision_box.size, rl.RED)
}

character_spawn_fireball :: proc(character: ^Character, objects: ^Dynamic_Objects) {
    dynamic_objects_push(objects, {
		position = character.position,
		lifetime_in_frames = 10,
	})
}

character_update :: proc(character: ^Character, world: ^World, input: rl.Vector2) {
    dt := rl.GetFrameTime()
    character.is_grounded = actor_is_on_floor(&character.actor, world)

    current_stats := Current_Stats {
        max_h_speed = character.stats.ground_move_speed,
        h_accel = character.stats.horizontal_acceleration,
        h_friction = character.stats.horizontal_friction,
    }

    if !character.is_grounded {
        current_stats.max_h_speed = character.stats.air_move_speed
        current_stats.h_accel = character.stats.air_acceleration
        current_stats.h_friction = character.stats.air_friction
    }

    switch state in character.state {
    case Character_State_Idle:
        character_idle_state(character, world, input, current_stats)
    case Character_State_Walking:
        character_walking_state(character, world, input, current_stats)
    case Character_State_Dash:
        character_dash_state(character, world, input, current_stats)
    }

    if character.velocity.y > character.stats.max_fall_speed {
        character.velocity.y = character.stats.max_fall_speed
    }

    if _, ok := actor_move_x(&character.actor, world, character.velocity.x * dt).?; ok {
        character.velocity.x = 0
    }
    if _, ok := actor_move_y(&character.actor, world, character.velocity.y * dt).?; ok {
        character.velocity.y = 0
    }
}

move_towards :: proc(current, target, max_delta: f32) -> f32 {
    if abs(target-current) <= max_delta {
        return target
    }

    return current + math.sign(target - current) * max_delta
}
