package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:net"
import "core:os"
import "core:slice"
import "core:thread"
import "core:time"
import rl "../vendor/raylib"

// Helper function to get max of two integers
max :: proc(a, b: int) -> int {
    return a > b ? a : b
}

// Simple rollback networking demo (without GGPO)
// This demonstrates the basic concepts of rollback networking

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600
PLAYER_SIZE :: 32
PLAYER_SPEED :: 3
MAX_ROLLBACK_FRAMES :: 8
FRAME_DELAY :: 2

// Input structure
Input :: struct {
	frame:                 u32,
	up, down, left, right: bool,
}

// Player state
Player_State :: struct {
	x, y:  f32,
	color: rl.Color,
}

// Game state that can be saved/restored
Game_State :: struct {
	players: [2]Player_State,
	frame:   u32,
}

// Network message types
Message_Type :: enum {
	INPUT,
	PING,
}

Network_Message :: struct {
	type:      Message_Type,
	frame:     u32,
	player_id: int,
	input:     Input,
}

// Rollback system
Rollback_System :: struct {
	// Circular buffer of game states
	states:          [MAX_ROLLBACK_FRAMES]Game_State,
	state_index:     int,

	// Input buffers for both players
	inputs:          [2][MAX_ROLLBACK_FRAMES]Input,
	input_index:     int,

	// Network
	socket:          net.UDP_Socket,
	remote_addr:     net.Endpoint,
	local_player:    int,

	// Timing
	last_frame_time: time.Time,
	frame_duration:  time.Duration,
}

rollback_system: Rollback_System
current_state: Game_State

// Initialize the rollback system
init_rollback_system :: proc(
	local_port: int,
	remote_ip: string,
	remote_port: int,
	is_player1: bool,
) -> bool {
	// Set up initial game state
	current_state = Game_State {
		players = {{x = 100, y = 100, color = rl.RED}, {x = 600, y = 400, color = rl.BLUE}},
		frame   = 0,
	}

	// Initialize rollback system
	rollback_system = {}
	rollback_system.local_player = is_player1 ? 0 : 1
	rollback_system.frame_duration = time.Millisecond * 16 // ~60 FPS

	// Initialize time with a zero value to ensure first frame processing happens immediately
	rollback_system.last_frame_time = {}

	// Set the state index and input index to avoid errors
	rollback_system.state_index = 0
	rollback_system.input_index = 0

	// Initialize input buffers with empty inputs for each frame
	// All should have frame 0 at the start to avoid invalid frame references
	for i in 0..<MAX_ROLLBACK_FRAMES {
		rollback_system.inputs[0][i] = Input{frame = 0}
		rollback_system.inputs[1][i] = Input{frame = 0}
	}

	// Initialize all states in the circular buffer
	for i in 0..<MAX_ROLLBACK_FRAMES {
		rollback_system.states[i] = current_state
	}

	// Set up networking
	local_address := net.IP4_Address{127, 0, 0, 1}
	socket_result, socket_err := net.make_bound_udp_socket(local_address, local_port)
	if socket_err != nil {
		fmt.printf("Failed to bind to port %d: %v\n", local_port, socket_err)
		return false
	}

	rollback_system.socket = socket_result
	rollback_system.remote_addr = net.Endpoint {
		address = net.IP4_Address{127, 0, 0, 1},
		port    = remote_port,
	}

	set_err := net.set_blocking(rollback_system.socket, false)
	if set_err != nil {
		fmt.printf("Failed to set socket to non-blocking mode: %v\n", set_err)
		return false
	}

	fmt.printf("Rollback system initialized on port %d\n", local_port)
	return true
}

// Save current state to rollback buffer
save_state :: proc(frame: u32) {
	index := int(frame) % MAX_ROLLBACK_FRAMES
	rollback_system.states[index] = current_state
	rollback_system.state_index = index  // Track last saved state index
}

// Load state from rollback buffer
load_state :: proc(frame: u32) {
	index := int(frame) % MAX_ROLLBACK_FRAMES
	current_state = rollback_system.states[index]
}

// Add input to buffer
add_input :: proc(player_id: int, input: Input) {
	index := int(input.frame) % MAX_ROLLBACK_FRAMES
	rollback_system.inputs[player_id][index] = input
	rollback_system.input_index = index  // Track last modified input index
}

// Get input from buffer
get_input :: proc(player_id: int, frame: u32) -> Input {
	index := int(frame) % MAX_ROLLBACK_FRAMES
	input := rollback_system.inputs[player_id][index]

	// Critical fix: Check if the input actually belongs to the requested frame
	// If not, it means we have no input for this frame yet (likely a prediction issue)
	if input.frame != frame {
		fmt.printf("Warning: Requested input for frame %d, but found input for frame %d\n", 
			frame, input.frame)

		// Create a predicted input based on previous frame
		prev_frame := frame > 0 ? frame - 1 : 0
		prev_idx := int(prev_frame) % MAX_ROLLBACK_FRAMES
		prev_input := rollback_system.inputs[player_id][prev_idx]

		// Create a new input with the proper frame number
		predicted_input := Input{
			frame = frame,
			up = prev_input.up,
			down = prev_input.down,
			left = prev_input.left,
			right = prev_input.right,
		}

		fmt.printf("Generated predicted input for P%d frame %d based on frame %d\n",
			player_id + 1, frame, prev_frame)

		// Save this predicted input in the buffer
		add_input(player_id, predicted_input)

		return predicted_input
	}

	return input
}

// Send input over network
send_input :: proc(input: Input) {
	message := Network_Message {
		type      = .INPUT,
		frame     = input.frame,
		player_id = rollback_system.local_player,
		input     = input,
	}

	// Simple JSON serialization for demo purposes
	json_data, json_err := json.marshal(message)
	if json_err != nil {
		fmt.printf("Failed to marshal message: %v\n", json_err)
		return
	}

	_, send_err := net.send_udp(rollback_system.socket, json_data, rollback_system.remote_addr)
	if send_err != nil {
		fmt.printf("Failed to send input: %v\n", send_err)
	}

	// Debug: output input state when it changes
	if input.up || input.down || input.left || input.right {
		fmt.printf("Sent P%d input for frame %d: UP=%v DOWN=%v LEFT=%v RIGHT=%v\n",
			rollback_system.local_player + 1, input.frame,
			input.up, input.down, input.left, input.right)
	}
}

// Receive input from network
receive_inputs :: proc() {
	buffer: [1024]byte

	for {
		bytes_read, _, recv_err := net.recv_udp(rollback_system.socket, buffer[:])
		if recv_err == .Would_Block {
			break // No more data
		}
		if recv_err != nil {
			fmt.printf("Failed to receive data: %v\n", recv_err)
			break
		}

		// Deserialize message
		message: Network_Message
		json_err := json.unmarshal(buffer[:bytes_read], &message)
		if json_err != nil {
			fmt.printf("Failed to unmarshal message: %v\n", json_err)
			continue
		}

		if message.type == .INPUT {
			// Debug: uncomment to see incoming inputs
			// fmt.printf("Received P%d input for frame %d (current frame: %d)\n",
			// 	message.player_id + 1, message.input.frame, current_state.frame)

			add_input(message.player_id, message.input)
		}
	}
}

// Apply input to game state
apply_input :: proc(player_id: int, input: Input) {
	if player_id < 0 || player_id >= 2 do return

	player := &current_state.players[player_id]

	// Track movement to debug
	original_x := player.x
	original_y := player.y

	// Apply movement - fixed to ensure movement actually happens
	if input.left {
		player.x -= PLAYER_SPEED
		fmt.printf("Moving player %d LEFT by %d pixels\n", player_id + 1, PLAYER_SPEED)
	}
	if input.right {
		player.x += PLAYER_SPEED
		fmt.printf("Moving player %d RIGHT by %d pixels\n", player_id + 1, PLAYER_SPEED)
	}
	if input.up {
		player.y -= PLAYER_SPEED
		fmt.printf("Moving player %d UP by %d pixels\n", player_id + 1, PLAYER_SPEED)
	}
	if input.down {
		player.y += PLAYER_SPEED
		fmt.printf("Moving player %d DOWN by %d pixels\n", player_id + 1, PLAYER_SPEED)
	}

	// Keep player in bounds
	if player.x < 0 {player.x = 0}
	if player.x > SCREEN_WIDTH - PLAYER_SIZE {player.x = SCREEN_WIDTH - PLAYER_SIZE}
	if player.y < 0 {player.y = 0}
	if player.y > SCREEN_HEIGHT - PLAYER_SIZE {player.y = SCREEN_HEIGHT - PLAYER_SIZE}

	// Always log movement regardless of whether it changed (helps debugging)
	fmt.printf("Frame %d: Player %d at position (%f, %f) after input application\n", 
		input.frame, player_id + 1, player.x, player.y)
}

// Simulate one frame of the game
simulate_frame :: proc(frame: u32) {
	// Apply inputs for all players
	for player_id in 0 ..< 2 {
		input := get_input(player_id, frame)

		// Ensure the input has the correct frame number
		input.frame = frame

		// Always log what inputs are being applied
		fmt.printf("Frame %d: Applying P%d input (up=%v, down=%v, left=%v, right=%v)\n",
			frame, player_id + 1, input.up, input.down, input.left, input.right)

		// Apply the input to move the player
		apply_input(player_id, input)
	}

	// Update the frame number in the state - this is critical for proper frame progression
	current_state.frame = frame
	fmt.printf("Frame %d has been simulated and current_state.frame is now %d\n", 
		frame, current_state.frame)

	// Print player positions after simulation
	fmt.printf("After frame %d simulation: P1(%f, %f) P2(%f, %f)\n", 
		frame, 
		current_state.players[0].x, current_state.players[0].y,
		current_state.players[1].x, current_state.players[1].y)
}

// Get current local input
get_local_input :: proc(frame: u32) -> Input {
	input := Input {
		frame = frame,
		up = rl.IsKeyDown(.UP) || rl.IsKeyDown(.W),
		down = rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S),
		left = rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A),
		right = rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D),
	}

	// Debug key state - only log when keys are pressed to avoid console spam
	if input.up || input.down || input.left || input.right {
		fmt.printf("Frame %d: Keys: UP=%v DOWN=%v LEFT=%v RIGHT=%v\n",
			frame, input.up, input.down, input.left, input.right)
	}

	return input
}

// Main rollback networking update
update_rollback :: proc() {
	current_time := time.now()

	// Receive any pending network inputs
	receive_inputs()

	// Get local input for this frame
	local_input := get_local_input(current_state.frame)
	add_input(rollback_system.local_player, local_input)
	send_input(local_input)

	// Create predicted remote input if none exists for current frame
	remote_player := rollback_system.local_player == 0 ? 1 : 0  // Define which player is remote
	remote_idx := int(current_state.frame) % MAX_ROLLBACK_FRAMES
	if rollback_system.inputs[remote_player][remote_idx].frame != current_state.frame {
		// Use previous frame's input as prediction
		prev_frame := current_state.frame > 0 ? current_state.frame - 1 : 0
		prev_idx := int(prev_frame) % MAX_ROLLBACK_FRAMES
		predicted_input := rollback_system.inputs[remote_player][prev_idx]
		predicted_input.frame = current_state.frame
		add_input(remote_player, predicted_input)
	}

	// Check if we need to rollback and resimulate due to newly received inputs
	// Find the earliest frame that needs resimulation
	earliest_dirty_frame := current_state.frame

	// Look back several frames to check for new remote inputs that might have arrived late
	for frame := max(0, int(current_state.frame) - MAX_ROLLBACK_FRAMES); frame < int(current_state.frame); frame += 1 {
		frame_idx := frame % MAX_ROLLBACK_FRAMES
		if rollback_system.inputs[remote_player][frame_idx].frame == u32(frame) {
			// If we have an input for a past frame, we might need to rollback
			if u32(frame) < earliest_dirty_frame {
				earliest_dirty_frame = u32(frame)
			}
		}
	}

	// If we need to rollback, do it
	if earliest_dirty_frame < current_state.frame {
		oldFrame := current_state.frame
		fmt.printf("Rolling back from frame %d to %d\n", current_state.frame, earliest_dirty_frame)

		// Load the state from the earliest dirty frame
		load_state(earliest_dirty_frame)

		// Important: Update the current state's frame to match the loaded state
		current_state.frame = earliest_dirty_frame

		// Store the old frame number for resimulation loop
		resimulate_to := oldFrame

		// Resimulate from that frame up to (but not including) the original frame
		for sim_frame := earliest_dirty_frame; sim_frame < resimulate_to; sim_frame += 1 {
			// Get inputs for this frame for both players
			local_input := get_input(rollback_system.local_player, sim_frame)
			remote_player := rollback_system.local_player == 0 ? 1 : 0
			remote_input := get_input(remote_player, sim_frame)

			// Debug the inputs being applied during rollback
			fmt.printf("Rollback resimulation frame %d: Local P%d input (UP=%v DOWN=%v LEFT=%v RIGHT=%v)\n", 
				sim_frame, rollback_system.local_player + 1, 
				local_input.up, local_input.down, local_input.left, local_input.right)
			fmt.printf("Rollback resimulation frame %d: Remote P%d input (UP=%v DOWN=%v LEFT=%v RIGHT=%v)\n", 
				sim_frame, remote_player + 1, 
				remote_input.up, remote_input.down, remote_input.left, remote_input.right)

			// Simulate this frame with both players' inputs
			simulate_frame(sim_frame)

			// Save the state after simulation
			save_state(sim_frame)
		}
	}

	// Save current state before simulation
	save_state(current_state.frame)

	// Simulate this frame
	simulate_frame(current_state.frame)

	// Debug frame advancement
	u32_old_frame := current_state.frame
	u32_new_frame := current_state.frame + 1
	fmt.printf("Advancing frame from %d to %d\n", u32_old_frame, u32_new_frame)

	// Advance frame - CRITICAL FIX: Ensure frame is incremented properly
	current_state.frame = u32_new_frame  // Explicitly set to the new frame number

	// Verify frame advancement and report errors
	if current_state.frame != u32_new_frame {
		fmt.printf("ERROR: Frame number did not advance! Still at frame %d\n", current_state.frame)
	}

	// Update timing for next frame
	rollback_system.last_frame_time = current_time
}


// Main demo
run_simple_rollback_demo :: proc(
	local_port: int,
	remote_ip: string,
	remote_port: int,
	is_player1: bool,
) {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Simple Rollback Networking Demo")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	if !init_rollback_system(local_port, remote_ip, remote_port, is_player1) {
		fmt.printf("Failed to initialize rollback system\n")
		return
	}
	defer net.close(rollback_system.socket)

	fmt.printf("Starting simple rollback demo...\n")
	fmt.printf(
		"You are Player %d (%s)\n",
		rollback_system.local_player + 1,
		rollback_system.local_player == 0 ? "RED" : "BLUE",
	)

	// Log initial state
	fmt.printf("Initial state set: P1 at (%f, %f), P2 at (%f, %f)\n",
		current_state.players[0].x, current_state.players[0].y,
		current_state.players[1].x, current_state.players[1].y)

	for !rl.WindowShouldClose() {
		// Frame start
		frame_start := time.now()

		// Save previous frame number to check if it changes
		previous_frame := current_state.frame

		// Normal rollback update
		update_rollback()

		// Verify the frame number actually changed
		if current_state.frame == previous_frame {
			fmt.printf("ERROR: Frame number did not advance! Still at frame %d\n", current_state.frame)
		}

		// EMERGENCY DIRECT INPUT - Bypass the rollback system if it's not working
		// This is just for debugging to make sure input works at all
		if rl.IsKeyDown(.LEFT_SHIFT) { // Hold shift to use direct input
			player := &current_state.players[rollback_system.local_player]
			original_x := player.x
			original_y := player.y

			if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) { player.y -= PLAYER_SPEED }
			if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) { player.y += PLAYER_SPEED }
			if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) { player.x -= PLAYER_SPEED }
			if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) { player.x += PLAYER_SPEED }

			// Keep player in bounds
			if player.x < 0 {player.x = 0}
			if player.x > SCREEN_WIDTH - PLAYER_SIZE {player.x = SCREEN_WIDTH - PLAYER_SIZE}
			if player.y < 0 {player.y = 0}
			if player.y > SCREEN_HEIGHT - PLAYER_SIZE {player.y = SCREEN_HEIGHT - PLAYER_SIZE}

			fmt.printf("DIRECT INPUT: Player moved from (%f, %f) to (%f, %f)\n", 
				original_x, original_y, player.x, player.y)
		}

		// Rate limiting - ensure we don't run too fast
		frame_time := time.diff(frame_start, time.now())
		target_frame_time := time.Millisecond * 16  // ~60 FPS
		if frame_time < target_frame_time {
			sleep_time := target_frame_time - frame_time
			time.sleep(sleep_time)
		}

		// Log frame processing information
		actual_frame_time := time.diff(frame_start, time.now())
		fmt.printf("Frame %d processed in %v\n", current_state.frame-1, actual_frame_time)

		// Render
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		// Draw players with improved visualization
		for i in 0 ..< 2 {
			player := current_state.players[i]

			// Draw player box
			rl.DrawRectangle(i32(player.x), i32(player.y), PLAYER_SIZE, PLAYER_SIZE, player.color)

			// Draw direction indicator (shows the last pressed direction)
			input_idx := int(current_state.frame-1) % MAX_ROLLBACK_FRAMES
			if input_idx >= 0 {
				input := rollback_system.inputs[i][input_idx]

				// Draw a small direction indicator
				center_x := i32(player.x) + PLAYER_SIZE/2
				center_y := i32(player.y) + PLAYER_SIZE/2

				if input.up { rl.DrawTriangle(rl.Vector2{f32(center_x), f32(center_y - 15)}, 
					                    rl.Vector2{f32(center_x - 5), f32(center_y - 5)}, 
					                    rl.Vector2{f32(center_x + 5), f32(center_y - 5)}, 
					                    rl.WHITE) }
				if input.down { rl.DrawTriangle(rl.Vector2{f32(center_x), f32(center_y + 15)}, 
					                      rl.Vector2{f32(center_x - 5), f32(center_y + 5)}, 
					                      rl.Vector2{f32(center_x + 5), f32(center_y + 5)}, 
					                      rl.WHITE) }
				if input.left { rl.DrawTriangle(rl.Vector2{f32(center_x - 15), f32(center_y)}, 
					                      rl.Vector2{f32(center_x - 5), f32(center_y - 5)}, 
					                      rl.Vector2{f32(center_x - 5), f32(center_y + 5)}, 
					                      rl.WHITE) }
				if input.right { rl.DrawTriangle(rl.Vector2{f32(center_x + 15), f32(center_y)}, 
					                       rl.Vector2{f32(center_x + 5), f32(center_y - 5)}, 
					                       rl.Vector2{f32(center_x + 5), f32(center_y + 5)}, 
					                       rl.WHITE) }
			}

			// Draw player label
			label := fmt.ctprintf("P%d", i + 1)
			rl.DrawText(label, i32(player.x), i32(player.y - 20), 16, rl.WHITE)

			// Draw coordinates below the player
			coords := fmt.ctprintf("(%.0f,%.0f)", player.x, player.y)
			rl.DrawText(coords, i32(player.x), i32(player.y + PLAYER_SIZE + 5), 12, rl.WHITE)
		}

		// Draw UI - show the current frame number prominently
		rl.DrawText(fmt.ctprintf("Frame: %d", current_state.frame), 10, 10, 24, rl.YELLOW)
		rl.DrawText(
			fmt.ctprintf(
				"You are Player %d (%s)",
				rollback_system.local_player + 1,
				rollback_system.local_player == 0 ? "RED" : "BLUE",
			),
			10,
			35,
			20,
			rl.WHITE,
		)

		// Debug: show current inputs and positions
		local_idx := int(current_state.frame-1) % MAX_ROLLBACK_FRAMES
		if local_idx >= 0 {
			local_input := rollback_system.inputs[rollback_system.local_player][local_idx]
			remote_input := rollback_system.inputs[rollback_system.local_player == 0 ? 1 : 0][local_idx]

			rl.DrawText(
				fmt.ctprintf("Local (P%d): UP=%v DOWN=%v LEFT=%v RIGHT=%v", 
					rollback_system.local_player + 1,
					local_input.up, local_input.down, local_input.left, local_input.right),
				10, 60, 16, rl.WHITE
			)
			rl.DrawText(
				fmt.ctprintf("Remote (P%d): UP=%v DOWN=%v LEFT=%v RIGHT=%v",
					rollback_system.local_player == 0 ? 2 : 1,
					remote_input.up, remote_input.down, remote_input.left, remote_input.right),
				10, 80, 16, rl.WHITE
			)
		}

		// Show player positions
		rl.DrawText(
			fmt.ctprintf("P1 Position: (%.1f, %.1f)", 
				current_state.players[0].x, current_state.players[0].y),
			10, 100, 16, rl.WHITE
		)
		rl.DrawText(
			fmt.ctprintf("P2 Position: (%.1f, %.1f)", 
				current_state.players[1].x, current_state.players[1].y),
			10, 120, 16, rl.WHITE
		)

		rl.DrawText("Use WASD or Arrow Keys to move", 10, SCREEN_HEIGHT - 30, 20, rl.WHITE)
		rl.DrawText("Hold LEFT SHIFT for direct input (bypasses rollback)", 10, SCREEN_HEIGHT - 55, 20, rl.GREEN)
		rl.DrawText("Simple Rollback Demo (No GGPO)", 10, SCREEN_HEIGHT - 80, 20, rl.YELLOW)

		rl.EndDrawing()
	}
}


main :: proc() {
	fmt.println("=== Simple Rollback Networking Demo ===")
	fmt.println("(GGPO alternative for macOS)")
	fmt.println()

	if len(os.args) < 2 {
		fmt.println("Usage:")
		fmt.println("  ./demo server   - Run as server (Player 1 - RED)")
		fmt.println("  ./demo client   - Run as client (Player 2 - BLUE)")
		fmt.println()
		return
	}

	mode := os.args[1]

	switch mode {
	case "server":
		fmt.println("🟥 Starting as server (Player 1 - RED)...")
		fmt.println("📡 Listening on port 8000...")
		fmt.println("⏳ Waiting for client to connect...")
		fmt.println()

		run_simple_rollback_demo(8000, "127.0.0.1", 8001, true)

	case "client":
		fmt.println("🟦 Starting as client (Player 2 - BLUE)...")
		fmt.println("📡 Running on port 8001...")
		fmt.println("🔗 Connecting to server on port 8000...")
		fmt.println()

		run_simple_rollback_demo(8001, "127.0.0.1", 8000, false)

	case:
		fmt.println("❌ Invalid mode. Use 'server' or 'client'")
		return
	}
}
