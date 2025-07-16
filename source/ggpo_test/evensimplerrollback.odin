package simpler_rollback

import "core:fmt"
import "core:time"
import "core:os"
import "core:net"
import rl "vendor:raylib"

Vector2 :: [2]f32

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600
PLAYER_SIZE :: 24
PLAYER_SPEED :: 5
HISTORY_SIZE :: 120
FRAME_DURATION :: time.Second / 60

Game_State :: struct {
    players: [2]Player,
    frame: u32,
}

Player :: struct {
    position: Vector2,
}

Input :: struct {
    axis: Vector2,
    frame: u32,
}

socket: net.UDP_Socket
remote_endpoint: net.Endpoint
network_init :: proc(local_port: u16, remote_port: u16) -> (err: net.Network_Error) {
    endpoint := net.resolve_ip4(fmt.tprintf("127.0.0.1:%d", local_port)) or_return
    socket = net.make_bound_udp_socket(endpoint.address, endpoint.port) or_return
    net.set_blocking(socket, false) or_return
    remote_endpoint = net.resolve_ip4(fmt.tprintf("127.0.0.1:%d", remote_port)) or_return

    return nil
}

game_state: Game_State
game_state_history: [HISTORY_SIZE]Game_State
input_history: [2][HISTORY_SIZE]Input

game_state_init :: proc() {
    game_state = Game_State {
        players = [2]Player {
            { position = {100, 300} },
            { position = {700, 300} },
        },
    }
}


game_state_update :: proc(state: Game_State, inputs: [2]Input) -> (next_state: Game_State) {
    next_state = state
    next_state.frame += 1
    for i in 0 ..< 2 {
        player := &next_state.players[i]
        player.position.x += inputs[i].axis.x * PLAYER_SPEED
        player.position.y += inputs[i].axis.y * PLAYER_SPEED

        // Bounds checking
        if player.position.x < 0 { player.position.x = 0 }
        if player.position.x > SCREEN_WIDTH - PLAYER_SIZE { player.position.x = SCREEN_WIDTH - PLAYER_SIZE }
        if player.position.y < 0 { player.position.y = 0 }
        if player.position.y > SCREEN_HEIGHT - PLAYER_SIZE { player.position.y = SCREEN_HEIGHT - PLAYER_SIZE }
    }
    return next_state
}

local_player_id: int
main :: proc() {
// Determine if we are player 1 or player 2 from command-line args.
    if len(os.args) < 2 || (os.args[1] != "p1" && os.args[1] != "p2") {
        fmt.println("Usage: odin run . p1|p2")
        return
    }

    if os.args[1] == "p1" {
        local_player_id = 0
        if err := network_init(9001, 9002); err != nil {
            fmt.eprintfln("error: %v", err)
            os.exit(1)
        }
        fmt.println("Running as Player 1 (ID ", local_player_id, "). Listening on port 9001, sending to 9002.")
    } else {
        local_player_id = 1
        if err := network_init(9002, 9001); err != nil {
            fmt.eprintfln("error: %v", err)
            os.exit(1)
        }
        fmt.println("Running as Player 2 (ID ", local_player_id, "). Listening on port 9002, sending to 9001.")
    }

    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, fmt.ctprintf("Simpler Rollback - Player %d", local_player_id + 1))
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    game_state_init()

    last_frame_time := time.now()
    for !rl.WindowShouldClose() {
    // --- Timing ---
    // Allow multiple simulation frames to run if rendering falls behind.
        for time.since(last_frame_time) >= FRAME_DURATION {

        // --- State Saving ---
            game_state_history[game_state.frame % HISTORY_SIZE] = game_state

            // --- Input Handling ---
            local_input := get_local_input(game_state.frame)
            input_bytes := transmute([size_of(Input)]byte)local_input
            if _, err := net.send_udp(socket, input_bytes[:], remote_endpoint); err != nil {
                fmt.println("error sending udp:", err)
            }
            input_history[local_player_id][game_state.frame % HISTORY_SIZE] = local_input

            // --- Rollback Check ---
            remote_player_id := 1 - local_player_id
            buffer: [size_of(Input)]byte
            for {
                n, _, err := net.recv_udp(socket, buffer[:])
                if err == .Would_Block { break }

                if n != size_of(Input) {
                    // drop packets that are invalid
                    continue
                }
                remote_input := transmute(Input)buffer

                frame := remote_input.frame
                if frame >= game_state.frame { continue } // Ignore inputs from the future

                history_idx := frame % HISTORY_SIZE
                recorded_input := input_history[remote_player_id][history_idx]
                if recorded_input.frame != frame || recorded_input.axis != remote_input.axis {
                    fmt.println("about to replay!", recorded_input, remote_input)
                    input_history[remote_player_id][history_idx] = remote_input

                    // Load state and re-simulate
                    rollback_state := game_state_history[frame % HISTORY_SIZE]
                    if rollback_state.frame != frame {
                        fmt.printf("cannot rollback to frame %d. state in history is for frame %d. input dropped",
                        frame,
                        rollback_state.frame)

                        continue
                    }
                    for f := frame; f < game_state.frame; f += 1 {
                        inputs := [2]Input{
                            input_history[0][f % HISTORY_SIZE],
                            input_history[1][f % HISTORY_SIZE],
                        }
                        rollback_state = game_state_update(rollback_state, inputs)
                        game_state_history[f % HISTORY_SIZE] = rollback_state
                    }
                    game_state = rollback_state
                }
            }

            // --- Simulation ---
            current_inputs: [2]Input
            current_inputs[local_player_id] = local_input

            // Predict remote input
            last_frame := game_state.frame - 1
            if game_state.frame == 0 { last_frame = 0 }
            last_input := input_history[remote_player_id][last_frame % HISTORY_SIZE]
            predicted_input := Input{frame = game_state.frame, axis = last_input.axis}
            current_inputs[remote_player_id] = predicted_input
            input_history[remote_player_id][game_state.frame % HISTORY_SIZE] = predicted_input

            game_state = game_state_update(game_state, current_inputs)

            last_frame_time = time.time_add(last_frame_time, FRAME_DURATION)
        }

        // --- Drawing ---
        // We always draw the latest game_state, regardless of how many simulation steps ran.
        draw_game()

    }
}


draw_game :: proc() {
    rl.BeginDrawing()
    defer rl.EndDrawing()

    rl.ClearBackground(rl.BLACK)

    p1_color := rl.RED
    p2_color := rl.BLUE
    if local_player_id == 1 {
        p1_color, p2_color = p2_color, p1_color
    }

    // Draw Players
    p1 := game_state.players[0]
    p2 := game_state.players[1]
    rl.DrawRectangle(i32(p1.position.x), i32(p1.position.y), PLAYER_SIZE, PLAYER_SIZE, p1_color)
    rl.DrawRectangle(i32(p2.position.x), i32(p2.position.y), PLAYER_SIZE, PLAYER_SIZE, p2_color)

    // Draw Text
    rl.DrawText(fmt.ctprintf("Frame: %d", game_state.frame), 10, 10, 20, rl.WHITE)
    rl.DrawText(fmt.ctprintf("You are Player %d", local_player_id + 1), 10, 40, 20, rl.WHITE)
    rl.DrawText("Use WASD or Arrow Keys", 10, SCREEN_HEIGHT - 30, 20, rl.WHITE)
}


get_local_input :: proc(frame: u32) -> Input {
    input := Input{frame = frame}

    if rl.IsKeyDown(.LEFT)  || rl.IsKeyDown(.A) { input.axis.x -= 1 }
    if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) { input.axis.x += 1 }
    if rl.IsKeyDown(.UP)    || rl.IsKeyDown(.W) { input.axis.y -= 1 }
    if rl.IsKeyDown(.DOWN)  || rl.IsKeyDown(.S) { input.axis.y += 1 }

    return input
}
