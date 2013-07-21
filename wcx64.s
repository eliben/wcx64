#------------- CONSTANTS --------------#
    .set O_RDONLY, 0x0
    .set OPEN_NO_MODE, 0x0
    .set READBUFLEN, 4096
#---------------- DATA ----------------#
    .data
newline_str:
    .asciz "\n"
buf_for_read:
    # leave space for terminating 0
    .space BUFLEN + 1, 0x0

#---------------- CODE ----------------#
    .globl _start
    .text
_start:

    # exit(0)
    mov $0, %rdi
    mov $60, %rax
    syscall

# Function print_cstring
#   Print a null-terminated string to stdout.
# Arguments:
#   rdi     address of string
# Returns: void
print_cstring:
    # Find the terminating null
    mov %rdi, %r10
.L_find_null:
    cmpb $0, (%r10)
    je .L_end_find_null
    inc %r10
    jmp .L_find_null
.L_end_find_null:
    # r10 points to the terminating null. so r10-rdi is the length
    sub %rdi, %r10

    # Now that we have the length, we can call sys_write
    # sys_write(unsigned fd, char* buf, size_t count)
    mov $1, %rax
    # Populate address of string into rsi first, because the later
    # assignment of fd clobbers rdi.
    mov %rdi, %rsi
    mov $1, %rdi
    mov %r10, %rdx
    syscall
    ret
