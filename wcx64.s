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
fourspace_str:
    .asciz "    "
buf_for_read:
    # leave space for terminating 0
    .space READBUFLEN + 1, 0x0
    # The itoa buffer here is large enough to hold just 11 digits (plus one
    # byte for the terminating null). For the wc counters this is enough
    # because it lets us represent 10-digit numbers (up to 10 GB)
    # with spaces in between.
    .set ITOABUFLEN, 12
buf_for_itoa:
    .space ITOABUFLEN, 0x0
    .set endbuf_for_itoa, buf_for_itoa + ITOABUFLEN - 1

#---------------- CODE ----------------#
    .globl _start
    .text
_start:
    mov (%rsp), %r12                # argc
    cmp $1, %r12
    jle .L_no_argv

    mov 16(%rsp), %r14
    # Call open(argv[1], O_RDONLY).
    mov 16(%rsp), %rdi
    mov $O_RDONLY, %rsi
    mov $OPEN_NO_MODE, %rdx
    mov $2, %rax
    syscall

    mov %rax, %rdi
    call count_in_file
    
    mov %rax, %rdi
    mov %rdx, %rsi
    mov %r9, %rdx
    mov %r14, %rcx
    call print_counters

    jmp .L_wcx64_exit

.L_no_argv:
    # Read from stdin
    mov $0, %rdi
    call count_in_file

    # Print the counters without a name string
    mov %rax, %rdi
    mov %rdx, %rsi
    mov %r9, %rdx
    mov $0, %rcx
    call print_counters

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

# Function print_counters
#   Print three counters with an optional name to stdout.
# Arguments:
#  rdi, rsi, rdx:   the counters
#  rcx:             address of the name C-string. If 0, no name is printed.
# Returns: void
print_counters:
    push %r14
    push %r15
    push %rdx
    push %rsi
    push %rdi
    mov %rcx, %r14

    # r15 is the counter pointer, running over 0, 1, 2
    # counter N is at (rsp + 8 * r15)
    xor %r15, %r15

.L_print_next_counter:
    # Fill the itoa buffer with spaces.
    lea buf_for_itoa, %rdi
    mov $SPACE, %rsi
    mov $ITOABUFLEN, %rdx
    call memset

    # Convert the next counter and then call print_cstring with the
    # beginning of the itoa buffer - because we want space-prefixed
    # output.
    mov (%rsp, %r15, 8), %rdi
    lea endbuf_for_itoa, %rsi
    call itoa
    lea buf_for_itoa, %rdi
    call print_cstring
    
    inc %r15
    cmp $3, %r15
    jl .L_print_next_counter

    # If rcx not 0, print out the given null-terminated string as well.
    cmp $0, %r14
    je .L_print_counters_done
    lea fourspace_str, %rdi
    call print_cstring
    mov %r14, %rdi
    call print_cstring

.L_print_counters_done:
    lea newline_str, %rdi
    call print_cstring
    pop %rdi
    pop %rsi
    pop %rdx
    pop %r15
    pop %r14
    ret

# Function memset
#   Fill memory with some byte
# Arguments:
#   rdi:    pointer to memory
#   rsi:    fill byte (in the low 8 bits)
#   rdx:    how many bytes to fill
# Returns: void
memset:
    xor %r10, %r10
.L_next_byte:
    movb %sil, (%rdi, %r10, 1)          # sil is rsi's low 8 bits
    inc %r10
    cmp %rdx, %r10
    jl .L_next_byte
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
