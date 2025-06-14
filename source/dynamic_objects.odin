package game

import rl "vendor:raylib"
import "core:container/small_array"

Dynamic_Objects :: small_array.Small_Array(25, Dynamic_Object)

Dynamic_Object :: struct {
	position: rl.Vector2,
	lifetime_in_frames: int,
}

dynamic_objects_update :: proc(dynamic_objects: ^Dynamic_Objects) {
	for &obj, i in small_array.slice(dynamic_objects) {
		obj.position.x += 10
		obj.lifetime_in_frames -= 1

		if obj.lifetime_in_frames <= 0 {
			small_array.unordered_remove(dynamic_objects, i)
		}
	}
}

dynamic_objects_draw :: proc(dynamic_objects: ^Dynamic_Objects) {
	for obj in small_array.slice(dynamic_objects) {
		rl.DrawRectangleV(obj.position, {10, 10}, rl.BLUE)
	}
}

dynamic_objects_push :: proc(dynamic_objects: ^Dynamic_Objects, object: Dynamic_Object) {
	small_array.push_back(dynamic_objects, object)
}