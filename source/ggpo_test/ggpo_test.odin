package gppotest

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "vendor:ggpo"
import rl "../vendor/raylib"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600
PLAYER_SIZE :: 32
PLAYER_SPEED :: 3

Input :: struct {
	up, down, left, right: bool,
}

Player_State :: struct {
	x, y:  f32,
	color: rl.Color,
}

Game_State :: struct {
	players: [2]Player_State,
	frame:   u32,
}

global_context: runtime.Context
game_state: Game_State
ggpo_session: ^ggpo.Session
player_handles: [2]ggpo.PlayerHandle
local_player: int = 0
session_callbacks: ggpo.SessionCallbacks

state_save_buffer: [size_of(Game_State)]u8

begin_game_callback :: proc "c" (game: cstring) -> bool {
	return true
}

save_game_state_callback :: proc "c" (
	buffer: ^[^]u8,
	len: ^i32,
	checksum: ^i32,
	frame: i32,
) -> bool {
	context = global_context

	state_size := size_of(Game_State)

	mem.copy(&state_save_buffer, &game_state, state_size)

	buffer^ = raw_data(state_buffer)
	len^ = i32(state_size)
	checksum^ = 0 // TODO: real checksum necessary

	return true
}

load_game_state_callback :: proc "c" (buffer: [^]u8, len: i32) -> bool {
	context = global_context

	mem.copy(&game_state, buffer, int(len))

	return true
}

log_game_state_callback :: proc "c" (filename: cstring, buffer: [^]u8, len: i32) -> bool {
	context = global_context

	state := cast(^Game_State)buffer
	fmt.printf(
		"Frame %d: P1(%f, %f) P2(%f, %f)\n",
		state.frame,
		state.players[0].x,
		state.players[0].y,
		state.players[1].x,
		state.players[1].y,
	)

	return true
}

free_buffer_callback :: proc "c" (buffer: rawptr) {}

advance_frame_callback :: proc "c" (flags: i32) -> bool {
	context = global_context

	inputs: [2]Input
	disconnect_flags: i32

	result := ggpo.synchronize_input(ggpo_session, &inputs, size_of(Input) * 2, &disconnect_flags)
	if result != .OK {
		fmt.printf("error synchronizing input: %v\n", result)
		return false
	}

	// Apply inputs to game state
	for i in 0 ..< 2 {
		if (disconnect_flags & (1 << uint(i))) == 0 { 	// Player is connected
			player := &game_state.players[i]
			input := inputs[i]

			if input.left {player.x -= PLAYER_SPEED}
			if input.right {player.x += PLAYER_SPEED}
			if input.up {player.y -= PLAYER_SPEED}
			if input.down {player.y += PLAYER_SPEED}

			// Keep player in bounds
			if player.x < 0 {player.x = 0}
			if player.x > SCREEN_WIDTH - PLAYER_SIZE {player.x = SCREEN_WIDTH - PLAYER_SIZE}
			if player.y < 0 {player.y = 0}
			if player.y > SCREEN_HEIGHT - PLAYER_SIZE {player.y = SCREEN_HEIGHT - PLAYER_SIZE}
		}
	}

	game_state.frame += 1
	ggpo.advance_frame(ggpo_session)

	return true
}

on_event_callback :: proc "c" (info: ^ggpo.Event) -> bool {
	context = global_context

	switch info.code {
	case .CONNECTED_TO_PEER:
		fmt.printf("Connected to peer\n")
	case .SYNCHRONIZING_WITH_PEER:
		fmt.printf(
			"Synchronizing with peer (%d/%d)\n",
			info.synchronizing.count,
			info.synchronizing.total,
		)
	case .SYNCHRONIZED_WITH_PEER:
		fmt.printf("Synchronized with peer\n")
	case .RUNNING:
		fmt.printf("Game is running!\n")
	case .DISCONNECTED_FROM_PEER:
		fmt.printf("Disconnected from peer\n")
	case .TIMESYNC:
		fmt.printf("Timesync: %d frames ahead\n", info.timesync.frames_ahead)
	case .CONNECTION_INTERRUPTED:
		fmt.printf("Connection interrupted\n")
	case .CONNECTION_RESUMED:
		fmt.printf("Connection resumed\n")
	}

	return true
}

init_ggpo :: proc(local_port: u16, remote_ip: string, remote_port: u16, is_player1: bool) -> bool {
	session_callbacks = ggpo.SessionCallbacks {
		begin_game      = begin_game_callback,
		save_game_state = save_game_state_callback,
		load_game_state = load_game_state_callback,
		log_game_state  = log_game_state_callback,
		free_buffer     = free_buffer_callback,
		advance_frame   = advance_frame_callback,
		on_event        = on_event_callback,
	}

	result := ggpo.start_session(
		&ggpo_session,
		&session_callbacks,
		"SimpleSquares",
		2,
		size_of(Input),
		local_port,
	)
	if result != .OK {
		fmt.printf("Failed to start GGPO session: %d\n", result)
		return false
	}

	local_player = is_player1 ? 0 : 1
	local_player_info := ggpo.Player {
		size       = size_of(ggpo.Player),
		type       = .LOCAL,
		player_num = i32(local_player + 1),
	}

	result = ggpo.add_player(ggpo_session, &local_player_info, &player_handles[local_player])
	if result != .OK {
		fmt.printf("Failed to add local player: %d\n", result)
		return false
	}

	remote_player := is_player1 ? 1 : 0
	remote_player_info := ggpo.Player {
		size       = size_of(ggpo.Player),
		type       = .REMOTE,
		player_num = i32(remote_player + 1),
	}

	ip_bytes: [32]u8
	copy(ip_bytes[:], remote_ip)
	copy(remote_player_info.remote.ip_address[:], ip_bytes[:])
	remote_player_info.remote.port = remote_port

	result = ggpo.add_player(ggpo_session, &remote_player_info, &player_handles[remote_player])
	if result != .OK {
		fmt.printf("Failed to add remote player: %d\n", result)
		return false
	}

	return true
}

init_game :: proc() {
	game_state = Game_State {
		players = {{x = 100, y = 100, color = rl.RED}, {x = 200, y = 200, color = rl.BLUE}},
		frame   = 0,
	}
}

get_input :: proc() -> Input {
	return Input {
		up = rl.IsKeyDown(.UP) || rl.IsKeyDown(.W),
		down = rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S),
		left = rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A),
		right = rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D),
	}
}

run_game :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "GGPO Simple Squares Game")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	init_game()

	if !init_ggpo(7000, "127.0.0.1", 7001, true) {
		fmt.printf("Failed to initialize GGPO\n")
		return
	}
	defer ggpo.close_session(ggpo_session)

	for !rl.WindowShouldClose() {
		ggpo.idle(ggpo_session, 0)
		input := get_input()
		result := ggpo.add_local_input(
			ggpo_session,
			player_handles[local_player],
			&input,
			size_of(Input),
		)
		if result != .OK {
			fmt.printf("Failed to add local input: %v\n", result)
		}

		rl.BeginDrawing()
		{
			rl.ClearBackground(rl.BLACK)
			for player in game_state.players {
				rl.DrawRectangle(
					i32(player.x),
					i32(player.y),
					PLAYER_SIZE,
					PLAYER_SIZE,
					player.color,
				)
			}
			rl.DrawText(fmt.ctprintf("Frame: %d", game_state.frame), 10, 10, 20, rl.WHITE)
			rl.DrawText(fmt.ctprintf("You are Player %d", local_player + 1), 10, 35, 20, rl.WHITE)
			rl.DrawText("Use WASD or Arrow Keys to move", 10, SCREEN_HEIGHT - 30, 20, rl.WHITE)
		}
		rl.EndDrawing()

	}
}
main :: proc() {
	global_context = context

	if len(os.args) < 2 {
		fmt.println("Usage:")
		fmt.println("  ./game server   - Run as server (player 1)")
		fmt.println("  ./game client   - Run as client (player 2)")
		return
	}

	mode := os.args[1]

	switch mode {
	case "server":
		fmt.println("Starting as server (Player 1)...")
		fmt.println("Waiting for client to connect on port 7001...")
		// Server runs on port 7000, expects client on port 7001
		if !init_ggpo(7000, "127.0.0.1", 7001, true) {
			fmt.println("Failed to initialize GGPO as server")
			return
		}

	case "client":
		fmt.println("Starting as client (Player 2)...")
		fmt.println("Connecting to server on port 7000...")
		// Client runs on port 7001, connects to server on port 7000
		if !init_ggpo(7001, "127.0.0.1", 7000, false) {
			fmt.println("Failed to initialize GGPO as client")
			return
		}

	case:
		fmt.println("Invalid mode. Use 'server' or 'client'")
		return
	}

	run_game()
}
