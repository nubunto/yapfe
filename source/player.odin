package game

import rl "vendor:raylib"

Player :: struct {
	using transform: Transform,

	id: int,
	texture: rl.Texture,
}

player_update :: proc(player: ^Player, input: rl.Vector2) {
	player.position += input * rl.GetFrameTime() * 100
}

player_draw :: proc(player: Player) {
	rl.DrawTextureEx(player.texture, player.position, 0, 1, rl.WHITE)
}

player_spawn_fireball :: proc(player: ^Player, objects: ^Dynamic_Objects) {
    dynamic_objects_push(objects, {
		position = g.player.position,
		lifetime_in_frames = 10,
	})
}
