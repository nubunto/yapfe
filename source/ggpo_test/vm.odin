package vm_fuck

import "core:fmt"

InstructionSet :: enum u8 {
    NOOP    = 0x00,
    LITERAL = 0x01,
    SUM     = 0x02,
    PRINT   = 0x03,
    SIZE_OF  = 0x04,
}

Stack :: struct($T: typeid, $N: uint = 128) {
    data:     [N]T,
    size:     uint,
}

stack_push :: proc(stack: ^Stack($T, $N), value: int) {
    assert(stack.size < N)
    stack.data[stack.size] = value
    stack.size += 1
}

stack_pop :: proc(stack: ^Stack($T, $N)) -> int {
    assert(stack.size > 0)
    stack.size -= 1
    ret := stack.data[stack.size]
    return ret
}

VM :: struct {
    code:  []u8,
    stack: Stack(int),
}

vm_interpret :: proc(vm: ^VM) {
    for i := 0; i < len(vm.code); i += 1 {
        bytecode := vm.code[i]
        switch InstructionSet(bytecode) {
        case InstructionSet.NOOP:
            continue
        case InstructionSet.LITERAL:
            val := vm.code[i + 1]
            stack_push(&vm.stack, int(val))
            i += 1
        case InstructionSet.SUM:
            val_1 := stack_pop(&vm.stack)
            val_2 := stack_pop(&vm.stack)
            stack_push(&vm.stack, val_1 + val_2)
        case InstructionSet.PRINT:
            fmt.println(stack_pop(&vm.stack))
        case InstructionSet.SIZE_OF:
            val := stack_pop(&vm.stack)
            stack_push(&vm.stack, size_of(val))
        }
    }
}

main :: proc() {
    code := []u8 {
        u8(InstructionSet.LITERAL),
        10,
        u8(InstructionSet.LITERAL),
        10,
        u8(InstructionSet.SUM),
        u8(InstructionSet.PRINT),
        u8(InstructionSet.LITERAL),
        10,
        u8(InstructionSet.SIZE_OF),
    }

    stack: Stack(int)

    vm := VM {
        code  = code,
        stack = stack,
    }

    vm_interpret(&vm)
}
