package enet_tutorial

import fmt "core:fmt"
import enet "vendor:ENet"

main :: proc() {

	if enet.initialize() != 0 {
		fmt.println("error in enet init")
		return
	}

	client := enet.host_create(nil, 1, 1, 0, 0)
	if client == nil {
		fmt.println("client error init")
		return
	}
	defer enet.host_destroy(client)

	address: enet.Address
	enet.address_set_host(&address, "127.0.0.1")
	address.port = 7777

	peer := enet.host_connect(client, &address, 1, 0)
	if peer == nil {
		fmt.println("No available peers for initiating an ENet connection!\n")
		return
	}
	defer enet.peer_disconnect(peer, 0)

	event: enet.Event
	for enet.host_service(client, &event, 5000) > 0 {
		#partial switch event.type {
		case .RECEIVE:
			fmt.printfln(
				"A packet of length %d containing '%s' was received from %v:%d on channel %d.\n",
				event.packet.dataLength,
				event.packet.data,
				event.peer.address.host,
				event.peer.address.port,
				event.channelID,
			)
			packet := enet.packet_create(event.packet.data, event.packet.dataLength, {.RELIABLE})
            enet.peer_send(event.peer, 0, packet)
		case .CONNECT:
			fmt.println("Connection to 127.0.0.1:7777 succeeded.")
			data := "some string"
			packet := enet.packet_create(raw_data(data), len(data), {.RELIABLE})
            enet.peer_send(event.peer, 0, packet)
		}
	}


}
