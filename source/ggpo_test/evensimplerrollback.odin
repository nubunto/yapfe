package simpler_rollback

import "core:fmt"
import "core:time"
import "core:os"
import "core:net"
import rl "../vendor/raylib"

Vector2 :: [2]f32

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600
PLAYER_SIZE :: 24
PLAYER_SPEED :: 5
HISTORY_SIZE :: 240
FRAME_DURATION :: time.Second / 60
MAX_ROLLBACK_FRAMES :: 16
MAX_PREDICT_FRAMES :: 8

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

Input_Packet :: struct {
    base_frame: u32,
    next_frame_needed: u32,
    input_count: u8,
    inputs: [MAX_ROLLBACK_FRAMES]Input,
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
confirmed_frame: [2]u32

game_state_init :: proc() {
    game_state = Game_State {
        players = [2]Player {
            { position = {100, 300} },
            { position = {700, 300} },
        },
    }
    confirmed_frame[0] = 0
    confirmed_frame[1] = 0
}

game_state_update :: proc(state: Game_State, inputs: [2]Input) -> (next_state: Game_State) {
    next_state = state
    next_state.frame += 1
    for i in 0 ..< 2 {
        player := &next_state.players[i]
        player.position.x += inputs[i].axis.x * PLAYER_SPEED
        player.position.y += inputs[i].axis.y * PLAYER_SPEED

        if player.position.x < 0 { player.position.x = 0 }
        if player.position.x > SCREEN_WIDTH - PLAYER_SIZE { player.position.x = SCREEN_WIDTH - PLAYER_SIZE }
        if player.position.y < 0 { player.position.y = 0 }
        if player.position.y > SCREEN_HEIGHT - PLAYER_SIZE { player.position.y = SCREEN_HEIGHT - PLAYER_SIZE }
    }
    return next_state
}

create_input_packet :: proc(local_player_id: int, current_frame: u32, remote_player_id: int) -> Input_Packet {
    packet := Input_Packet{}
    packet.base_frame = current_frame
    packet.next_frame_needed = confirmed_frame[remote_player_id] + 1
    
    input_count := 0
    for i := 0; i < MAX_ROLLBACK_FRAMES && i <= int(current_frame); i += 1 {
        frame := current_frame - u32(i)
        if frame < confirmed_frame[local_player_id] {
            break
        }
        
        packet.inputs[input_count] = input_history[local_player_id][frame % HISTORY_SIZE]
        input_count += 1
    }
    packet.input_count = u8(input_count)
    
    return packet
}

process_input_packet :: proc(packet: Input_Packet, from_player: int) -> (bool, u32) {
    remote_player := 1 - from_player
    remote_frame := packet.base_frame
    
    if packet.next_frame_needed > confirmed_frame[remote_player] {
        confirmed_frame[remote_player] = packet.next_frame_needed - 1
    }
    
    rollback_needed := false
    earliest_rollback_frame := game_state.frame
    
    for i := 0; i < len(packet.inputs); i += 1 {
        input := packet.inputs[i]
        if input.frame == 0 {
            continue
        }
        
        history_idx := input.frame % HISTORY_SIZE
        
        if input_history[remote_player][history_idx].frame == input.frame {
            continue
        }
        
        input_history[remote_player][history_idx] = input
        
        if input.frame < game_state.frame {
            predicted := predict_input(remote_player, input.frame)
            input_magnitude := math.sqrt(input.axis[0]*input.axis[0] + input.axis[1]*input.axis[1])
            predicted_magnitude := math.sqrt(predicted.axis[0]*predicted.axis[0] + predicted.axis[1]*predicted.axis[1])
            
            if math.abs(input_magnitude - predicted_magnitude) > 0.1 && 
               input.frame < game_state.frame - 1 {
                
                fmt.printf("P%d: Input correction at frame %d - was: %v, now: %v\n", 
                          remote_player, input.frame, predicted, input)
                rollback_needed = true
                if input.frame < earliest_rollback_frame {
                    earliest_rollback_frame = input.frame
                    if game_state.frame - earliest_rollback_frame > MAX_ROLLBACK_FRAMES {
                        earliest_rollback_frame = game_state.frame - MAX_ROLLBACK_FRAMES
                    }
                }
            }
        }
    }
    
    return rollback_needed, earliest_rollback_frame
}

perform_rollback :: proc(rollback_frame: u32) -> bool {
    if rollback_frame >= game_state.frame {
        return false
    }
    
    if game_state.frame - rollback_frame >= HISTORY_SIZE {
        fmt.printf("Cannot rollback: frame %d is too far back (current: %d)\n", 
                  rollback_frame, game_state.frame)
        return false
    }
    
    target_frame := rollback_frame
    for target_frame > 0 {
        history_idx := target_frame % HISTORY_SIZE
        if game_state_history[history_idx].frame == target_frame {
            break
        }
        target_frame -= 1
    }
    
    if target_frame == 0 && game_state_history[0].frame != 0 {
        fmt.printf("No valid state found for rollback to frame %d\n", rollback_frame)
        return false
    }
    
    fmt.printf("Rolling back from frame %d to frame %d\n", game_state.frame, target_frame)
    
    rollback_state := game_state_history[target_frame % HISTORY_SIZE]
    
    for f := target_frame; f < game_state.frame; f += 1 {
        inputs := [2]Input{
            input_history[0][f % HISTORY_SIZE],
            input_history[1][f % HISTORY_SIZE],
        }
        rollback_state = game_state_update(rollback_state, inputs)
    }
    
    game_state = rollback_state
    return true
}

predict_input :: proc(player: int, frame: u32) -> Input {
    history_idx := frame % HISTORY_SIZE
    if input_history[player][history_idx].frame == frame {
        return input_history[player][history_idx]
    }
    
    for i := frame - 1; i > 0 && i > frame - 10; i -= 1 {
        idx := i % HISTORY_SIZE
        if input_history[player][idx].frame == i {
            result := input_history[player][idx]
            result.frame = frame
            return result
        }
    }
    
    return Input{frame = frame}
}

local_player_id: int
main :: proc() {
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

    game_started := false
    last_frame_time := time.now()
    
    for !rl.WindowShouldClose() {
        for time.since(last_frame_time) >= FRAME_DURATION {
            game_state_history[game_state.frame % HISTORY_SIZE] = game_state

            local_input := get_local_input(game_state.frame)
            input_history[local_player_id][game_state.frame % HISTORY_SIZE] = local_input

            remote_player_id := 1 - local_player_id
            packet := create_input_packet(local_player_id, game_state.frame, remote_player_id)
            packet_bytes := transmute([size_of(Input_Packet)]byte)packet
            
            if _, err := net.send_udp(socket, packet_bytes[:], remote_endpoint); err != nil {
                fmt.println("error sending udp:", err)
            }

            rollback_needed := false
            earliest_rollback_frame := game_state.frame
            
            buffer: [size_of(Input_Packet)]byte
            for {
                n, _, err := net.recv_udp(socket, buffer[:])
                if err != nil {
                    break
                }
                if n != size_of(Input_Packet) {
                    continue
                }

                if !game_started {
                    fmt.println("Remote player connected!")
                    game_started = true
                }

                received_packet := transmute(Input_Packet)buffer
                rollback, earliest_rollback_frame := process_input_packet(received_packet, remote_player_id)
                if rollback {
                    rollback_needed = true
                }
            }

            if rollback_needed {
                if !perform_rollback(earliest_rollback_frame) {
                    fmt.println("Rollback failed, continuing from current state")
                }
            }

            if game_started {
                current_inputs: [2]Input
                current_inputs[local_player_id] = local_input

                remote_input := input_history[remote_player_id][game_state.frame % HISTORY_SIZE]
                if remote_input.frame != game_state.frame {
                    remote_input = predict_input(remote_player_id, game_state.frame)
                    input_history[remote_player_id][game_state.frame % HISTORY_SIZE] = remote_input
                    fmt.printf("P%d: Predicting input for frame %d: %v\n", local_player_id + 1, game_state.frame, remote_input.axis)
                }

                current_inputs[remote_player_id] = remote_input
                game_state = game_state_update(game_state, current_inputs)
            }

            last_frame_time = time.time_add(last_frame_time, FRAME_DURATION)
        }

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

    // Draw UI
    rl.DrawText(fmt.ctprintf("Frame: %d", game_state.frame), 10, 10, 20, rl.WHITE)
    rl.DrawText(fmt.ctprintf("Player %d", local_player_id + 1), 10, 40, 20, rl.WHITE)
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
