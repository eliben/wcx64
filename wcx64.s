#------------- CONSTANTS --------------#
    .set O_RDONLY, 0x0
    .set OPEN_NO_MODE, 0x0
    .set READBUFLEN, 4096
    .set NEWLINE, '\n'
    .set CR, '\r'
    .set TAB, '\t'
    .set SPACE, ' '
#---------------- DATA ----------------#
    .data
newline_str:
    .asciz "\n"
buf_for_read:
    # leave space for terminating 0
    .space READBUFLEN + 1, 0x0

#---------------- CODE ----------------#
    .globl _start
    .text
_start:

    # exit(0)
    mov $0, %rdi
    mov $60, %rax
    syscall

# Function count_in_file
#   Counts chars, words and lines for a single file.
# Arguments:
#   rdi     file descriptor representing an open file.
# Returns:
#   rax     line count
#   rdx     word count
#   r9      char count
count_in_file:
    # Register usage within the function:
    #
    # rdi: holds the fd
    # r8: next byte read from the buffer
    # r9: char counter
    # r10: word counter
    # r11: line counter
    # r13: address of the read buffer
    # rcx: loop index for going over a read buffer
    # r12: state indicator, with the states defined below
    .set IN_WORD, 1
    .set IN_WHITESPACE, 2
    # In addition, rsi, rdx, rax are used in the call to read().
    # After each call to read(), rax is used for its return value.

    xor %r9, %r9
    xor %r10, %r10
    xor %r11, %r11
    lea buf_for_read, %r13
    mov $IN_WHITESPACE, %r12

.L_read_buf:
    # Call read(fd, buf_for_read, READBUFLEN). rdi already contains fd
    mov %buf_for_read, %rsi
    mov $READBUFLEN, %rdx
    mov $0, %rax
    syscall

    # From here on, rax holds the amount of bytes actually read from the
    # file (the return value of read())
    add %rax, %r9               # Update the char counter
    xor %rcx, %rcx

.L_next_byte_in_buf:
    movb (%r13, %rax, 1), %r8
    # ZZZ: here
    inc %rcx
    cmp %rcx, %rax
    jne .L_next_byte_in_buf

    ret

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
