package game

import rl "vendor:raylib"
import "core:math/linalg"
import "core:fmt"
Player :: struct {
	using character: Character,
	id: int,
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

	return linalg.normalize0(input)
}


player_update :: proc(player: ^Player, world: ^World) {
	input := player_get_input()
	character_update(&player.character, world, input)

	if rl.IsKeyPressed(.F) {
		character_spawn_fireball(&player.character, &g.dynamic_objects)
	}

	if rl.IsKeyPressed(.SPACE) {
		character_try_jump(&player.character, &g.world)
	}
}

player_draw :: proc(player: ^Player) {
	character_draw(player.character)
}

player_draw_debug :: proc(player: ^Player) {
	rl.DrawText(fmt.ctprintf("player_pos: %v", player.position), 5, 5, 7, rl.YELLOW)
	rl.DrawText(fmt.ctprintf("player_state: %v", player.state), 5, 15, 7, rl.YELLOW)
	rl.DrawText(fmt.ctprintf("player_velocity: %v", player.character.velocity), 5, 25, 7, rl.YELLOW)
}