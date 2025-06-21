/*
This file is the starting point of your game.

Some important procedures are:
- game_init_window: Opens the window
- game_init: Sets up the game state
- game_update: Run once per frame
- game_should_close: For stopping your game when close button is pressed
- game_shutdown: Shuts down game and frees memory
- game_shutdown_window: Closes window

The procs above are used regardless if you compile using the `build_release`
script or the `build_hot_reload` script. However, in the hot reload case, the
contents of this file is compiled as part of `build/hot_reload/game.dll` (or
.dylib/.so on mac/linux). In the hot reload cases some other procedures are
also used in order to facilitate the hot reload functionality:

- game_memory: Run just before a hot reload. That way game_hot_reload.exe has a
	pointer to the game's memory that it can hand to the new game DLL.
- game_hot_reloaded: Run after a hot reload so that the `g` global
	variable can be set to whatever pointer it was in the old DLL.

NOTE: When compiled as part of `build_release`, `build_debug` or `build_web`
then this whole package is just treated as a normal Odin package. No DLL is
created.
*/

package game

import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 180
frame_by_frame_mode: bool

Game_Memory :: struct {
	dynamic_objects:      Dynamic_Objects,
	player:               Player,
	world:                World,
	run:                  bool,
	global_frame_counter: u64,
}

g: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {zoom = h / PIXEL_WINDOW_HEIGHT, target = g.player.position, offset = {w / 2, h / 2}}
}

ui_camera :: proc() -> rl.Camera2D {
	return {zoom = f32(rl.GetScreenHeight()) / PIXEL_WINDOW_HEIGHT}
}

update :: proc() {
	g.global_frame_counter += 1

	if frame_by_frame_mode {
		if rl.IsKeyPressed(.F2) {
			player_update(&g.player, &g.world, g.global_frame_counter)
			dynamic_objects_update(&g.dynamic_objects)
		}
	} else {
		player_update(&g.player, &g.world, g.global_frame_counter)
		dynamic_objects_update(&g.dynamic_objects)
	}

	if rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}

	// reset player position
	if rl.IsKeyPressed(.R) {
		g.player.position = {100, -80}
		g.player.velocity = {0, 0}
	}

	if rl.IsKeyPressed(.F1) {
		frame_by_frame_mode = !frame_by_frame_mode
	}

}

draw :: proc() {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.DARKGRAY)

	draw_with_camera(game_camera(), proc() {
		player_draw_debug(&g.player)
		player_draw(g.player)

		solids_iter := world_make_solids_iterator(&g.world)
		for solid in world_solids_iter(&solids_iter) {
			rl.DrawRectangleV(solid.position, solid.collision_box.size, rl.GREEN)
		}

		dynamic_objects_draw(&g.dynamic_objects)
	})

	draw_with_camera(ui_camera(), proc() {
		rl.DrawFPS(3, 5)
		if frame_by_frame_mode {
			rl.DrawText("Frame by frame mode", 3, 20, 2, rl.WHITE)
		}
	})
}

draw_with_camera :: proc(camera: rl.Camera2D, draw_fn: proc()) {
	rl.BeginMode2D(camera)
	defer rl.EndMode2D()

	draw_fn()
}

@(export)
game_update :: proc() {
	update()
	draw()

	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Odin + Raylib + Hot Reload template!")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(120)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	g = new(Game_Memory)

	character: Character
	character.stats = Character_Stats {
		dash_speed               = 150,
		running_speed            = 170,
		horizontal_acceleration  = 10,
		horizontal_friction      = 600,
		jump_force               = 240,
		gravity                  = {0, 500},
		air_move_speed           = 120,
		air_acceleration         = 90,
		air_friction             = 10,
		max_horizontal_air_speed = 160,
		max_fall_speed           = 250,
	}
	character.position = {100, -80}
	character.collision_box = CollisionBox2D {
		size = {13, 20},
	}

	player := Player {
		character = character,
	}

	world: World

	world_push_actor(&world, character.actor)
	world_push_solid(
		&world,
		Solid2D {
			position = {-10, -20},
			collision_box = CollisionBox2D{size = {50, 10}},
			collidable = true,
		},
	)
	world_push_solid(
		&world,
		Solid2D {
			position = {10, -20},
			collision_box = CollisionBox2D{size = {50, 10}},
			collidable = true,
		},
	)
	world_push_solid(
		&world,
		Solid2D {
			position = {30, -20},
			collision_box = CollisionBox2D{size = {50, 10}},
			collidable = true,
		},
	)
	world_push_solid(
		&world,
		Solid2D {
			position = {50, -20},
			collision_box = CollisionBox2D{size = {50, 10}},
			collidable = true,
		},
	)
	world_push_solid(
		&world,
		Solid2D {
			position = {110, -20},
			collision_box = CollisionBox2D{size = {50, 10}},
			collidable = true,
		},
	)
	world_push_solid(
		&world,
		Solid2D {
			position = {170, -20},
			collision_box = CollisionBox2D{size = {50, 10}},
			collidable = true,
		},
	)
	world_push_solid(
		&world,
		Solid2D {
			position = {10, 20},
			collision_box = CollisionBox2D{size = {1000, 10}},
			collidable = true,
		},
	)

	g^ = Game_Memory {
		run    = true,
		player = player,
		world  = world,
	}

	game_hot_reloaded(g)
}

@(export)
game_should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			return false
		}
	}

	return g.run
}

@(export)
game_shutdown :: proc() {
	free(g)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}
