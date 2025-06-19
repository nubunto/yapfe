package game

import "base:intrinsics"
import rl "vendor:raylib"
import math "core:math"
import "core:fmt"
// import "core:reflect"

DEFAULT_DASH_DURATION_FRAMES :: u8(24)

Character_Stats :: struct {
    running_speed: f32,
    walking_speed: f32,
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
    Character_State_Running,
    // more to come!
}

Character_State_Idle :: struct {
}

Character_State_Walking :: struct {
}

Character_State_Running :: struct {
}

Character_State_Dash :: struct {
    duration_in_frames: u8,
}

init_state_dash :: proc(duration := DEFAULT_DASH_DURATION_FRAMES) -> Character_State_Dash {
    return {
        duration_in_frames = duration,
    }
}

Character :: struct {
    using actor: Actor2D,
    stats: Character_Stats,
    state: Character_Default_State,
    velocity: rl.Vector2,
    direction: i8,
    direction_last_frame: i8,
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
            character.state = init_state_dash()
        } else {
            // character.state = Character_State_Walking {
            //     direction = i8(math.sign(input.x)),
            // }
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

character_running_state :: proc(character: ^Character, world: ^World, input: rl.Vector2, stats: Current_Stats) {
    _, ok := &character.state.(Character_State_Running)
    if !ok {
        return
    }

    max_h_speed := stats.max_h_speed
    h_accel := stats.h_accel

    if character.direction_last_frame != character.direction && character.direction != 0 {
        character.state = init_state_dash()
    }

    if input.x == 0 {
        character.state = Character_State_Idle{}
        return
    }

    character.velocity.x = move_towards(character.velocity.x, (input.x * max_h_speed), h_accel * rl.GetFrameTime())
    apply_gravity(character, world)
}

character_dash_state :: proc(character: ^Character, world: ^World, input: rl.Vector2, stats: Current_Stats) {
    if input.x == 0 {
        character.state = Character_State_Idle{}
        return
    }

    state, ok := &character.state.(Character_State_Dash)
    if !ok {
        return
    }

    state.duration_in_frames -= 1
    if state.duration_in_frames <= 0 {
        character.state = Character_State_Running{}
    }

    character.velocity.x = input.x * character.stats.dash_speed
    apply_gravity(character, world)
}

character_draw :: proc(character: Character) {
	rl.DrawRectangleV(character.position, character.collision_box.size, rl.RED)
}

character_draw_debug :: proc(character: Character) {
	draw_text_debug(fmt.ctprintf("player_pos: %v", character.position), 1, character.position)
	draw_text_debug(fmt.ctprintf("player_vel: %v", character.velocity), 2, character.position)
	draw_text_debug(fmt.ctprintf("player_direction: %v", character.direction), 3, character.position)
	draw_text_debug(fmt.ctprintf("state: %v", character.state), 4, character.position)
}

draw_text_debug :: proc(text: cstring, offset: i32, position: [2]f32) {
    offset_y := offset * 10
    start_of_region: [2]i32 = { i32(position.x - 45), i32(position.y - 45) }

	rl.DrawText(text, start_of_region.x, start_of_region.y + offset_y, 1, rl.YELLOW)
	rl.DrawText(text, start_of_region.x, start_of_region.y + offset_y, 1, rl.YELLOW)
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
    character.direction_last_frame = character.direction
    character.direction = i8(math.sign(input.x))

    current_stats := Current_Stats {
        max_h_speed = character.stats.running_speed,
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
    case Character_State_Running:
        character_running_state(character, world, input, current_stats)
    }

    character.velocity.y = min(character.velocity.y, character.stats.max_fall_speed)

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
