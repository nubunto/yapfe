package game

import sa "core:container/small_array"
import "core:fmt"
import "core:math/linalg"
import rl "vendor:raylib"

Player :: struct {
	using character: Character,
	id:              int,
	current_input:   Action,
	input_buffer:    sa.Small_Array(256, Buffered_Input),
}

Action_Input :: struct {
	vector: rl.Vector2,
}

Action_Jump :: struct {}

Action_Attack :: struct {}

Action :: union {
	Action_Input,
	Action_Jump,
	Action_Attack,
}

Buffered_Input :: struct {
	action:        Action,
	frame_created: u64,
	is_consumed:   bool,
}

Input_State :: struct {
	input_vector: rl.Vector2,
}

player_get_input :: proc() -> rl.Vector2 {
	input: rl.Vector2

	if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {
		input.y -= 1
	}
	if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {
		input.y += 1
	}
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
		input.x -= 1
	}
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
		input.x += 1
	}

	return input
}

player_invalidate_buffer :: proc(
	player: ^Player,
	current_frame: u64,
	buffer_duration_frames: u64,
) {
	// invalidate old inputs
	for i := sa.len(player.input_buffer) - 1; i >= 0; i -= 1 {
		buffered_input := sa.get(player.input_buffer, i)
		if current_frame - buffered_input.frame_created > u64(buffer_duration_frames) {
			sa.ordered_remove(&player.input_buffer, i)
		}
	}
}

player_buffer_new_input :: proc(player: ^Player, action: Action, current_frame: u64) {
	new_buffered_input := Buffered_Input {
		action        = action,
		frame_created = current_frame,
		is_consumed   = false,
	}
	sa.push(&player.input_buffer, new_buffered_input)
}

player_was_action_pressed_consume :: proc(
	buffer: ^sa.Small_Array($N, Buffered_Input),
	action: Action,
) -> bool {
	for i := sa.len(buffer^) - 1; i >= 0; i -= 1 {
		buffered_input, ok := sa.get_ptr_safe(buffer, i)
		if !ok {
			continue
		}
		if buffered_input.action == action && !buffered_input.is_consumed {
			buffered_input.is_consumed = true
			return true
		}
	}
	return false
}

player_buffer_inputs :: proc(player: ^Player, frame: u64) {
	input := player_get_input()
	if linalg.length(input) > 1 {
		player_buffer_new_input(player, Action_Input{vector = input}, frame)
	}

	if rl.IsKeyPressed(.SPACE) {
		player_buffer_new_input(player, Action_Jump{}, frame)
	}

	if rl.IsKeyPressed(.F) {
		player_buffer_new_input(player, Action_Attack{}, frame)
	}
}

player_update :: proc(player: ^Player, world: ^World, frame: u64) {
	input := player_get_input()
	character_update(&player.character, world, input, &player.input_buffer)

	if rl.IsKeyPressed(.F) {
		// character_spawn_fireball(&player.character, &g.dynamic_objects)

	}


}

player_draw :: proc(player: Player) {
	character_draw(player.character)
}

player_draw_debug :: proc(player: ^Player) {
	character_draw_debug(player)
	// fmt.printfln("player_buffer: %v", player.input_buffer)
	buffer := sa.slice(&player.input_buffer)

	if len(buffer) >= 3 {
		fmt.printfln("last 3 actions buffered: %v", buffer[len(buffer) - 3:])
	}
	// rl.DrawText(fmt.ctprintf("player_pos: %v", player.position), 5, 5, 1, rl.YELLOW)
	// rl.DrawText(fmt.ctprintf("player_velocity: %v", player.character.velocity), 5, 15, 1, rl.YELLOW)
	// rl.DrawText(fmt.ctprintf("player_state: %v", player.state), 5, 25, 1, rl.YELLOW)
	// rl.DrawText(fmt.ctprintf("character direction: %v", player.direction), 5, 35, 1, rl.YELLOW)
}
