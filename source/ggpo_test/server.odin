package enet_tutorial

import fmt "core:fmt"
import enet "vendor:ENet"

main :: proc() {
    if enet.initialize() != 0 {
        fmt.println("An error occurred while initializing ENet.")
        return
    }
    defer enet.deinitialize()

    address: enet.Address
    address.host = enet.HOST_ANY
    address.port = 7777

    server := enet.host_create(&address, 32, 1, 0, 0)
    if server == nil {
        fmt.println("An error occurred while trying to create an ENet server host.")
        return
    }
    defer enet.host_destroy(server)

    fmt.println("ENet server started on port 7777.")

    event: enet.Event
    for {
        for enet.host_service(server, &event, 1000) > 0 {
            #partial switch event.type {
            case .CONNECT:
                fmt.printf("A new client connected from %x:%u.\n", event.peer.address.host, event.peer.address.port)
                event.peer.data = "Client information"
            case .RECEIVE:
                fmt.printf("A packet of length %u containing %s was received from %s on channel %u.\n",
                    event.packet.dataLength,
                    event.packet.data,
                    event.peer.data,
                    event.channelID)
                
                // Echo the packet back to the sender
                packet := enet.packet_create(event.packet.data, event.packet.dataLength, .RELIABLE)
                enet.peer_send(event.peer, 0, packet)

            case .DISCONNECT:
                fmt.printf("%s disconnected.\n", event.peer.data)
                // Reset the peer's client information.
                event.peer.data = nil
            }
        }
    }
}
