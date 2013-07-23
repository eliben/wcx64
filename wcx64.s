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
    # We need buf_for_itoa to be large enough to contain a 64-bit integer.
    # endbuf_for_itoa will point to the end of buf_for_itoa and is useful
    # for passing to itoa.
    .set BUFLEN, 32
buf_for_itoa:
    .space BUFLEN, 0x0
    .set endbuf_for_itoa, buf_for_itoa + BUFLEN - 1

#---------------- CODE ----------------#
    .globl _start
    .text
_start:
    mov (%rsp), %r12                # argc
    cmp $1, %r12
    jle .L_no_argv

    # Call open(argv[1], O_RDONLY).
    mov 16(%rsp), %rdi
    mov $O_RDONLY, %rsi
    mov $OPEN_NO_MODE, %rdx
    mov $2, %rax
    syscall

    mov %rax, %rdi
    call count_in_file

    mov %rax, %r13
    mov %rdx, %r14
    mov %r9, %r15

    mov %r13, %rdi
    lea endbuf_for_itoa, %rsi
    call itoa
    mov %rax, %rdi
    call print_cstring
    lea newline_str, %rdi
    call print_cstring

    mov %r14, %rdi
    lea endbuf_for_itoa, %rsi
    call itoa
    mov %rax, %rdi
    call print_cstring
    lea newline_str, %rdi
    call print_cstring

    mov %r15, %rdi
    lea endbuf_for_itoa, %rsi
    call itoa
    mov %rax, %rdi
    call print_cstring
    lea newline_str, %rdi
    call print_cstring

    jmp .L_wcx64_exit

.L_no_argv:
    # Read from stdin
    mov $0, %rdi
    call count_in_file

    mov %rax, %r13
    mov %rdx, %r14
    mov %r9, %r15

    mov %r13, %rdi
    lea endbuf_for_itoa, %rsi
    call itoa
    mov %rax, %rdi
    call print_cstring
    lea newline_str, %rdi
    call print_cstring

.L_wcx64_exit:
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
    # Save callee-saved registers.
    push %r12
    push %r13
    push %r14
    push %r15
    # Register usage within the function:
    #
    # rdi: holds the fd
    # dl: next byte read from the buffer
    # r9: char counter
    # r15: word counter
    # r14: line counter
    # r13: address of the read buffer
    # rcx: loop index for going over a read buffer
    # r12: state indicator, with the states defined below.
    #      the word counter is incremented when we switch from IN_WHITESPACE
    #      to IN_WORD.
    .set IN_WORD, 1
    .set IN_WHITESPACE, 2
    # In addition, rsi, rdx, rax are used in the call to read().
    # After each call to read(), rax is used for its return value.

    xor %r9, %r9
    xor %r15, %r15
    mov $0, %r14
    lea buf_for_read, %r13
    mov $IN_WHITESPACE, %r12

.L_read_buf:
    # Call read(fd, buf_for_read, READBUFLEN). rdi already contains fd
    mov %r13, %rsi
    mov $READBUFLEN, %rdx
    mov $0, %rax
    syscall

    # From here on, rax holds the amount of bytes actually read from the
    # file (the return value of read())
    add %rax, %r9               # Update the char counter
    xor %rcx, %rcx

.L_next_byte_in_buf:
    movb (%r13, %rcx, 1), %dl           # Read the byte

    # See what we've got and jump to the appropriate label.
    cmp $NEWLINE, %dl
    je .L_seen_newline
    cmp $CR, %dl
    je .L_seen_whitespace_not_newline
    cmp $SPACE, %dl
    je .L_seen_whitespace_not_newline
    cmp $TAB, %dl
    je .L_seen_whitespace_not_newline
    # else, it's not whitespace but a part of a word
    cmp $IN_WORD, %r12
    je .L_done_with_this_byte
    inc %r15
    mov $IN_WORD, %r12
    jmp .L_done_with_this_byte
.L_seen_newline:
    inc %r14
.L_seen_whitespace_not_newline:
    cmp $IN_WORD, %r12
    je .L_end_current_word
    # Otherwise, still in newline
    jmp .L_done_with_this_byte
.L_end_current_word:
    mov $IN_WHITESPACE, %r12
.L_done_with_this_byte:
    inc %rcx
    cmp %rcx, %rax
    jne .L_next_byte_in_buf

    # Done going over this buffer. We need to read another buffer
    # if rax == READBUFLEN.
    cmp $READBUFLEN, %rax
    je .L_read_buf

    # Done with this file. The char count is already in r9.
    # Put the word and line counts in their return locations.
    mov %r15, %rdx
    mov %r14, %rax

    # Restore callee-saved registers.
    pop %r15
    pop %r14
    pop %r13
    pop %r12
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

# Function itoa
#   Convert an integer to a null-terminated string in memory.
#   Assumes that there is enough space allocated in the target
#   buffer for the representation of the integer. Since the number itself
#   is accepted in the register, its value is bounded.
# Arguments:
#   rdi:    the integer
#   rsi:    address of the *last* byte in the target buffer
# Returns:
#   rax:    address of the first byte in the target string that
#           contains valid information.
itoa:
    movb $0, (%rsi)        # Write the terminating null and advance.
    dec %rsi

    # If the input number is negative, we mark it by placing 1 into r9
    # and negate it. In the end we check if r9 is 1 and add a '-' in front.
    mov $0, %r9
    cmp $0, %rdi
    jge .L_input_positive
    neg %rdi
    mov $1, %r9
.L_input_positive:

    mov %rdi, %rax          # Place the number into rax for the division.
    mov $10, %r8            # The base is in r8

.L_next_digit:
    # Prepare rdx:rax for division by clearing rdx. rax remains from the
    # previous div. rax will be rax / 10, rdx will be the next digit to
    # write out.
    xor %rdx, %rdx
    div %r8
    # Write the digit to the buffer, in ascii
    dec %rsi
    add $0x30, %dl
    movb %dl, (%rsi)

    cmp $0, %rax            # We're done when the quotient is 0.
    jne .L_next_digit

    # If we marked in r9 that the input is negative, it's time to add that
    # '-' in front of the output.
    cmp $1, %r9
    jne .L_itoa_done
    dec %rsi
    movb $0x2d, (%rsi)

.L_itoa_done:
    mov %rsi, %rax          # rsi points to the first byte now; return it.
    ret
