package game

import "base:intrinsics"
import sa "core:container/small_array"
import math "core:math"
import rl "vendor:raylib"

DEFAULT_DASH_DURATION_FRAMES :: u8(14)
DEFAULT_JUMPSQUAT_FRAMES :: u8(5)

Character_Stats :: struct {
	running_speed:            f32,
	walking_speed:            f32,
	dash_speed:               f32,
	horizontal_acceleration:  f32,
	horizontal_friction:      f32,
	jump_force:               f32,
	max_horizontal_air_speed: f32,
	air_acceleration:         f32,
	air_friction:             f32,
	max_fall_speed:           f32,
	gravity:                  rl.Vector2,
}

Character_Attack_ID :: enum {
	Normal,
	Special,
}

Character_Default_State :: union #no_nil {
	Character_State_Idle,
	Character_State_Walking,
	Character_State_Dash,
	Character_State_Running,
	Character_State_Aerial,
	Character_State_Jumpsquat,
	Character_State_NormalAttack,
	// more to come!
}

Character_State_Idle :: struct {}

Character_State_Walking :: struct {}

Character_State_Running :: struct {}

Character_State_Jumpsquat :: struct {
	jumpsquat_frames: u8,
}

Character_State_Aerial :: struct {}

Attack_State :: enum {
	Startup,
	Active,
	Recovery,
}

Attack_Stats :: struct {
	startup_frames:  uint,
	active_frames:   uint,
	recovery_frames: uint,
}

Character_State_NormalAttack :: struct {
	current_state:         Attack_State,
	current_frame_counter: uint,
	stats:                 Attack_Stats,
	collision_box:         CollisionBox2D,
	position_offset:       rl.Vector2,
}

init_state_jumpsquat :: proc(
	jumpsquat_frames := DEFAULT_JUMPSQUAT_FRAMES,
) -> Character_State_Jumpsquat {
	return {jumpsquat_frames = jumpsquat_frames}
}

Character_State_Dash :: struct {
	duration_in_frames: u8,
}

init_state_dash :: proc(duration := DEFAULT_DASH_DURATION_FRAMES) -> Character_State_Dash {
	return {duration_in_frames = duration}
}

Character_Attack_Definition :: struct {
	stats:     Attack_Stats,
	offset:    rl.Vector2,
	collision: CollisionBox2D,
}

Character :: struct {
	using actor:          Actor2D,
	stats:                Character_Stats,
	state:                Character_Default_State,
	velocity:             rl.Vector2,
	direction:            i8,
	direction_last_frame: i8,
	is_grounded:          bool,
	attacks:              [Character_Attack_ID]Character_Attack_Definition,
}

apply_gravity :: proc(character: ^Character, world: ^World) {
	if !actor_is_on_floor(&character.actor, world) {
		character.velocity.y += character.stats.gravity.y * rl.GetFrameTime()
	}
}

apply_friction :: proc(character: ^Character, friction: f32) {
	character.velocity.x = move_towards(character.velocity.x, 0, friction * rl.GetFrameTime())
}

character_try_jump :: proc(character: ^Character, world: ^World) {
	if actor_is_on_floor(&character.actor, world) {
		character.state = init_state_jumpsquat()
	}
}

character_idle_state :: proc(
	character: ^Character,
	world: ^World,
	input: rl.Vector2,
	buffer: ^sa.Small_Array($N, Buffered_Input),
) {
	direction := math.sign(input.x)
	if direction != 0 {
		character.direction = i8(direction)
	}

	if !actor_is_on_floor(character, world) {
		character.state = Character_State_Aerial{}
		return
	}

	if _, jumped := player_was_action_pressed_consume(buffer, Action_Jump{}); jumped {
		character_try_jump(character, world)
		return
	}

	if input.y == 1 {
		// TODO: platdrop
		character.non_collidable = true
	}

	if _, attacked := player_was_action_pressed_consume(buffer, Action_Attack{}); attacked {
		character_attack := character.attacks[.Normal]
		character.state = Character_State_NormalAttack {
			current_frame_counter = character_attack.stats.startup_frames,
			stats                 = character_attack.stats,
			collision_box         = character_attack.collision,
			position_offset       = character_attack.offset,
		}
	}

	apply_gravity(character, world)

	if input.x == 0 {
		friction :=
			character.is_grounded ? character.stats.horizontal_friction : character.stats.air_friction
		apply_friction(character, friction)
	} else {
		character.state = init_state_dash()
	}
}

character_walking_state :: proc(
	character: ^Character,
	world: ^World,
	input: rl.Vector2,
	buffer: ^sa.Small_Array($N, Buffered_Input),
) {
	_, ok := &character.state.(Character_State_Walking)
	if !ok {
		return
	}

	if _, jumped := player_was_action_pressed_consume(buffer, Action_Jump{}); jumped {
		character_try_jump(character, world)
		return
	}
	if input.x == 0 {
		character.state = Character_State_Idle{}
		return
	}

	character.velocity.x = move_towards(
		character.velocity.x,
		input.x * character.stats.walking_speed,
		character.stats.horizontal_acceleration * rl.GetFrameTime(),
	)
	apply_gravity(character, world)
}

character_running_state :: proc(
	character: ^Character,
	world: ^World,
	input: rl.Vector2,
	buffer: ^sa.Small_Array($N, Buffered_Input),
) {
	_, ok := &character.state.(Character_State_Running)
	if !ok {
		return
	}

	if !actor_is_on_floor(character, world) {
		character.state = Character_State_Aerial{}
		return
	}

	if _, jumped := player_was_action_pressed_consume(buffer, Action_Jump{}); jumped {
		character_try_jump(character, world)
		return
	}

	max_h_speed := character.stats.running_speed

	if character.direction_last_frame != character.direction && character.direction != 0 {
		character.state = init_state_dash()
	}

	if input.x == 0 {
		character.state = Character_State_Idle{}
		return
	}

	character.velocity.x = move_towards(
		character.velocity.x,
		(input.x * max_h_speed),
		character.stats.horizontal_acceleration * rl.GetFrameTime(),
	)
	apply_gravity(character, world)
}

character_dash_state :: proc(
	character: ^Character,
	world: ^World,
	input: rl.Vector2,
	buffer: ^sa.Small_Array($N, Buffered_Input),
) {
	state, ok := &character.state.(Character_State_Dash)
	if !ok {
		return
	}

	if input.x == 0 {
		character.state = Character_State_Idle{}
		return
	}

	if _, jumped := player_was_action_pressed_consume(buffer, Action_Jump{}); jumped {
		character_try_jump(character, world)
		return
	}

	state.duration_in_frames -= 1
	if state.duration_in_frames <= 0 {
		character.state = Character_State_Running{}
	}

	character.velocity.x = input.x * character.stats.dash_speed
	apply_gravity(character, world)
}

character_jumpsquat_state :: proc(
	character: ^Character,
	world: ^World,
	input: rl.Vector2,
	buffer: ^sa.Small_Array($N, Buffered_Input),
) {
	state, state_ok := &character.state.(Character_State_Jumpsquat)
	if !state_ok {
		return
	}

	if state.jumpsquat_frames <= 0 {
		character.velocity.y = -character.stats.jump_force
		character.non_collidable = true
		character.state = Character_State_Aerial{}
		return
	}

	state.jumpsquat_frames = max(state.jumpsquat_frames - 1, 0)
}

character_aerial_state :: proc(
	character: ^Character,
	world: ^World,
	input: rl.Vector2,
	buffer: ^sa.Small_Array($N, Buffered_Input),
) {
	_, state_ok := &character.state.(Character_State_Aerial)
	if !state_ok {
		return
	}

	if input.x == 0 {
		apply_friction(character, character.stats.air_friction)
	} else {
		character.velocity.x = move_towards(
			character.velocity.x,
			input.x * character.stats.max_horizontal_air_speed,
			character.stats.air_acceleration * rl.GetFrameTime(),
		)
	}

	apply_gravity(character, world)

	if character.velocity.y >= 0 {
		character.non_collidable = false
		if actor_is_on_floor(character, world) {
			character.state = Character_State_Idle{}
		}
	}
}

character_normalattack_state :: proc(
	character: ^Character,
	world: ^World,
	input: rl.Vector2,
	buffer: ^sa.Small_Array($N, Buffered_Input),
) {
	state, ok := &character.state.(Character_State_NormalAttack)
	if !ok {
		return
	}

	state.current_frame_counter = max(state.current_frame_counter - 1, 0)

	switch state.current_state {
	case Attack_State.Startup:
		if state.current_frame_counter == 0 {
			state.current_state = Attack_State.Active
			state.current_frame_counter = state.stats.active_frames
		}
	case Attack_State.Active:
		// TODO: draw stuff and check for collisions
		if state.current_frame_counter == 0 {
			state.current_state = Attack_State.Recovery
			state.current_frame_counter = state.stats.recovery_frames
		}
	case Attack_State.Recovery:
		// TODO: no longer check for collision and draw stuff
		if state.current_frame_counter <= 0 {
			character.state = Character_State_Idle{}
		}
	}
}

character_draw :: proc(character: Character) {
	#partial switch state in character.state {
	case Character_State_Jumpsquat:
		// //
		// if state.jumpsquat_frames <= 0 {
		//     rl.DrawRectangleV(character.position, character.collision_box.size, rl.RED)
		//     break
		// }

		// poor man's stretch and squash
		progress := 1.0 - (f32(state.jumpsquat_frames) / f32(DEFAULT_JUMPSQUAT_FRAMES))

		original_size := character.collision_box.size
		// squash to be wider and shorter
		squashed_size := rl.Vector2{original_size.x * 2.3, original_size.y * 0.3}

		current_size := vector2_lerp(original_size, squashed_size, progress)

		// adjust position to keep the base of the character on the same spot
		draw_pos := rl.Vector2 {
			character.position.x - (current_size.x - original_size.x) / 2,
			character.position.y + (original_size.y - current_size.y),
		}

		rl.DrawRectangleV(draw_pos, current_size, rl.RED)
	case Character_State_NormalAttack:
		flipped := rl.Vector2 {
			f32(character.direction) * state.position_offset.x,
			state.position_offset.y,
		}
		attack_pos := character.position + flipped
		rl.DrawRectangleV(character.position, character.collision_box.size, rl.RED)
		rl.DrawRectangleV(attack_pos, state.collision_box.size, rl.PURPLE)
	case:
		flipped := rl.Vector2{f32(character.direction) * 15, 0}
		character_center := rl.Vector2 {
			character.position.x + (character.collision_box.size.x / 2),
			character.position.y + (character.collision_box.size.y / 2),
		}
		rl.DrawRectangleV(character.position, character.collision_box.size, rl.RED)
		rl.DrawRectangleV(character_center + flipped, {7, 7}, rl.GREEN)
	// TODO: figure out how to draw a small direction indicator
	// too sleepy for this shit
	// rl.DrawRectangleV({ character.position.x * f32(character.direction), character.position.y}, {15, 2}, rl.LIME)
	}
}

character_draw_debug :: proc(character: Character) {
	draw_text_debug(rl.TextFormat("input: %v", player_get_input()), 0, character.position)
	draw_text_debug(rl.TextFormat("player_pos: %v", character.position), 1, character.position)
	draw_text_debug(rl.TextFormat("player_vel: %v", character.velocity), 2, character.position)
	draw_text_debug(
		rl.TextFormat("player_direction: %v", character.direction),
		3,
		character.position,
	)
	draw_text_debug(rl.TextFormat("state: %v", character.state), 4, character.position)
}

draw_text_debug :: proc(text: cstring, offset: i32, position: [2]f32) {
	offset_y := offset * 10
	start_of_region: [2]i32 = {i32(position.x - 145), i32(position.y - 45)}

	rl.DrawText(text, start_of_region.x, start_of_region.y + offset_y, 1, rl.YELLOW)
	rl.DrawText(text, start_of_region.x, start_of_region.y + offset_y, 1, rl.YELLOW)
}

character_spawn_fireball :: proc(character: ^Character, objects: ^Dynamic_Objects) {
	dynamic_objects_push(objects, {position = character.position, lifetime_in_frames = 10})
}

character_update :: proc(
	character: ^Character,
	world: ^World,
	input: rl.Vector2,
	buffer: ^sa.Small_Array($N, Buffered_Input),
) {
	dt := rl.GetFrameTime()
	character.is_grounded = actor_is_on_floor(&character.actor, world)
	character.direction_last_frame = character.direction

	switch state in character.state {
	case Character_State_Idle:
		character_idle_state(character, world, input, buffer)
	case Character_State_Walking:
		character_walking_state(character, world, input, buffer)
	case Character_State_Dash:
		character_dash_state(character, world, input, buffer)
	case Character_State_Running:
		character_running_state(character, world, input, buffer)
	case Character_State_Aerial:
		character_aerial_state(character, world, input, buffer)
	case Character_State_Jumpsquat:
		character_jumpsquat_state(character, world, input, buffer)
	case Character_State_NormalAttack:
		character_normalattack_state(character, world, input, buffer)
	}

	apply_velocity(character, world, dt)
}

apply_velocity :: proc(character: ^Character, world: ^World, dt: f32) {
	character.velocity.y = min(character.velocity.y, character.stats.max_fall_speed)

	if cinfo := actor_move_x(&character.actor, world, character.velocity.x * dt);
	   collision_info_stops_movement(cinfo) {
		character.velocity.x = 0
	}
	if cinfo := actor_move_y(&character.actor, world, character.velocity.y * dt);
	   collision_info_stops_movement(cinfo) {
		character.velocity.y = 0
	}
}

vector2_lerp :: proc(a, b: rl.Vector2, t: f32) -> rl.Vector2 {
	return {a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t}
}

move_towards :: proc(current, target, max_delta: f32) -> f32 {
	if abs(target - current) <= max_delta {
		return target
	}

	return current + math.sign(target - current) * max_delta
}
