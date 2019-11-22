#-------------------------------------------------------------------------------
# wcx64: a simplistic wc clone in x64 assembly. Usage:
#
# $ wcx64 file1 /path/file2 file3
#
# When not given any command-line arguments, reads from stdin.
# Always prints the all three counters: line, word, byte.
#
# Eli Bendersky (eliben@gmail.com)
# This code is in the public domain
#-------------------------------------------------------------------------------

#------------- CONSTANTS --------------#
.set READ_SYSCALL, 0
.set WRITE_SYSCALL, 1
.set OPEN_SYSCALL, 2
.set CLOSE_SYSCALL, 3
.set EXIT_SYSCALL, 60
.set STDIN_FD, 0
.set STDOUT_FD, 1

.set O_RDONLY, 0x0
.set OPEN_NO_MODE, 0x0
.set READBUFLEN, 16384
.set ITOABUFLEN, 12
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

total_str:
    .asciz "total"

buf_for_read:
    # leave space for terminating 0
    .space READBUFLEN + 1, 0x0

    # The itoa buffer here is large enough to hold just 11 digits (plus one
    # byte for the terminating null). For the wc counters this is enough
    # because it lets us represent 10-digit numbers (up to 10 GB)
    # with spaces in between.
    # Note: this is an artificial limitation for simplicity in printing out the
    # counters; this size can be easily increased.
buf_for_itoa:
    .space ITOABUFLEN, 0x0
    .set   endbuf_for_itoa, buf_for_itoa + ITOABUFLEN - 1

#---------------- "MAIN" CODE ----------------#
    .globl _start
    .text

_start:
    # If there are no argv, go to .L_no_argv for reading from
    # stdin.
    mov (%rsp), %rbx                # (%rsp) is argc
    cmp $1, %rbx
    jle .L_no_argv

    xor %r13, %r13
    xor %r14, %r14
    xor %r15, %r15

    # In a loop, argv[n] for 1 <= n < argc; rbp holds n.
    mov $1, %rbp

.L_argv_loop:
    # Throughout the loop, register assignments:
    # r12: argv[n]. Also gets into rdi for passing into the open() syscall
    # rbp: argv counter n
    # rbx: holds argc
    # r13, r14, r15: total numbers counted in all files.
    mov 8(%rsp, %rbp, 8), %rdi      # argv[n] is in (rsp + 8 + 8*n)
    mov %rdi, %r12

    # Call open(argv[n], O_RDONLY).
    mov $O_RDONLY, %rsi
    mov $OPEN_NO_MODE, %rdx
    mov $OPEN_SYSCALL, %rax
    syscall

    # Ignore files that can't be opened
    cmp  $0, %rax
    jl   .L_next_argv
    push %rax                       # save fd on the stack

    mov  %rax, %rdi
    call count_in_file

    # Add the counters returned from count_in_file to the totals and pass
    # them to print_counters.
    mov  %rax, %rdi
    add  %rax, %r13
    mov  %rdx, %rsi
    add  %rdx, %r14
    mov  %r9, %rdx
    add  %r9, %r15
    mov  %r12, %rcx
    call print_counters

    # Call close(argv[n])
    pop %rdi                        # restore fd from the stack
    mov $CLOSE_SYSCALL, %rax
    syscall

.L_next_argv:
    inc %rbp
    cmp %rbx, %rbp
    jl  .L_argv_loop

    # Done with all argv. Now print out the totals.
    mov  %r13, %rdi
    mov  %r14, %rsi
    mov  %r15, %rdx
    lea  total_str, %rcx
    call print_counters

    jmp .L_wcx64_exit

.L_no_argv:
    # Read from stdin, which is file descriptor 0.
    mov  $STDIN_FD, %rdi
    call count_in_file

    # Print the counters without a name string
    mov  %rax, %rdi
    mov  %rdx, %rsi
    mov  %r9, %rdx
    mov  $0, %rcx
    call print_counters

.L_wcx64_exit:
    # exit(0)
    mov $0, %rdi
    mov $EXIT_SYSCALL, %rax
    syscall
    ret

#---------------- FUNCTIONS ----------------#

# Function count_in_file
# Counts chars, words and lines for a single file.
#
# Arguments:
# rdi     file descriptor representing an open file.
#
# Returns:
# rax     line count
# rdx     word count
# r9      char count
count_in_file:
    # Save callee-saved registers.
    push %r12
    push %r13
    push %r14
    push %r15

    # Register usage within the function:
    #
    # rdi: holds the fd
    # r9: char counter
    # r15: word counter
    # r14: line counter
    # r13: address of the read buffer
    # rcx: loop index for going over a read buffer
    # dl: next byte read from the buffer
    # r12: state indicator, with the states defined below.
    # the word counter is incremented when we switch from
    # IN_WHITESPACE to IN_WORD.
    .set IN_WORD, 1
    .set IN_WHITESPACE, 2

    # In addition, rsi, rdx, rax are used in the call to read().
    # After each call to read(), rax is used for its return value.
    xor %r9, %r9
    xor %r15, %r15
    xor %r14, %r14
    lea buf_for_read, %r13
    mov $IN_WHITESPACE, %r12

.L_read_buf:
    # Call read(fd, buf_for_read, READBUFLEN). rdi already contains fd
    mov %r13, %rsi
    mov $READBUFLEN, %rdx
    mov $READ_SYSCALL, %rax
    syscall

    # From here on, rax holds the number of bytes actually read from the
    # file (the return value of read())
    add %rax, %r9                       # Update the char counter

    cmp $0, %rax                        # No bytes read?
    je  .L_done_with_file

    xor %rcx, %rcx
.L_next_byte_in_buf:
    movb (%r13, %rcx, 1), %dl           # Read the byte

    # See what we've got and jump to the appropriate label.
    cmp $NEWLINE, %dl
    je  .L_seen_newline
    cmp $CR, %dl
    je  .L_seen_whitespace_not_newline
    cmp $SPACE, %dl
    je  .L_seen_whitespace_not_newline
    cmp $TAB, %dl
    je  .L_seen_whitespace_not_newline
    # else, it's not whitespace but a part of a word.

    # If we're in a word already, nothing else to do.
    cmp $IN_WORD, %r12
    je  .L_done_with_this_byte
    # else, transition from IN_WHITESPACE to IN_WORD: increment the word
    # counter.
    inc %r15
    mov $IN_WORD, %r12
    jmp .L_done_with_this_byte

.L_seen_newline:
    # Increment the line counter and fall through.
    inc %r14

.L_seen_whitespace_not_newline:
    cmp $IN_WORD, %r12
    je  .L_end_current_word
    # Otherwise, still in whitespace.
    jmp .L_done_with_this_byte

.L_end_current_word:
    mov $IN_WHITESPACE, %r12

.L_done_with_this_byte:
    # Advance read pointer and check if we haven't finished with the read
    # buffer yet.
    inc %rcx
    cmp %rcx, %rax
    jg  .L_next_byte_in_buf

    # Done going over this buffer. We need to read another buffer
    # if rax == READBUFLEN.
    cmp $READBUFLEN, %rax
    je  .L_read_buf

.L_done_with_file:
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
# Print a null-terminated string to stdout.
#
# Arguments:
# rdi     address of string
#
# Returns: void
print_cstring:
    # Find the terminating null
    mov %rdi, %r10
.L_find_null:
    cmpb $0, (%r10)
    je   .L_end_find_null
    inc  %r10
    jmp  .L_find_null

.L_end_find_null:
    # r10 points to the terminating null. so r10-rdi is the length
    sub %rdi, %r10
    # Now that we have the length, we can call sys_write
    # sys_write(unsigned fd, char* buf, size_t count)
    mov $WRITE_SYSCALL, %rax
    # Populate address of string into rsi first, because the later
    # assignment of fd clobbers rdi.
    mov %rdi, %rsi
    mov $STDOUT_FD, %rdi
    mov %r10, %rdx
    syscall
    ret

# Function print_counters
# Print three counters with an optional name to stdout.
#
# Arguments:
# rdi, rsi, rdx:   the counters
# rcx:             address of the name C-string. If 0, no name is printed.
#
# Returns: void
print_counters:
    push %r14
    push %r15
    push %rdx
    push %rsi
    push %rdi
    # rcx can be clobbered by callees, so save it in %r14.
    mov  %rcx, %r14

    # r15 is the counter pointer, running over 0, 1, 2
    # counter N is at (rsp + 8 * r15)
    xor %r15, %r15

.L_print_next_counter:
    # Fill the itoa buffer with spaces.
    lea  buf_for_itoa, %rdi
    mov  $SPACE, %rsi
    mov  $ITOABUFLEN, %rdx
    call memset
    # Convert the next counter and then call print_cstring with the
    # beginning of the itoa buffer - because we want space-prefixed
    # output.
    mov  (%rsp, %r15, 8), %rdi
    lea  endbuf_for_itoa, %rsi
    call itoa
    lea  buf_for_itoa, %rdi
    call print_cstring
    inc %r15
    cmp $3, %r15
    jl  .L_print_next_counter

    # If name address is not 0, print out the given null-terminated string
    # as well.
    cmp  $0, %r14
    je   .L_print_counters_done
    lea  fourspace_str, %rdi
    call print_cstring
    mov  %r14, %rdi
    call print_cstring

.L_print_counters_done:
    lea  newline_str, %rdi
    call print_cstring
    pop  %rdi
    pop  %rsi
    pop  %rdx
    pop  %r15
    pop  %r14
    ret

# Function memset
# Fill memory with some byte
#
# Arguments:
# rdi:    pointer to memory
# rsi:    fill byte (in the low 8 bits)
# rdx:    how many bytes to fill
#
# Returns: void
memset:
    xor %r10, %r10

.L_next_byte:
    movb %sil, (%rdi, %r10, 1)          # sil is rsi's low 8 bits
    inc  %r10
    cmp  %rdx, %r10
    jl   .L_next_byte
    ret

# Function itoa
# Convert an integer to a null-terminated string in memory.
# Assumes that there is enough space allocated in the target
# buffer for the representation of the integer. Since the number itself
# is accepted in the register, its value is bounded.
#
# Arguments:
# rdi:    the integer
# rsi:    address of the *last* byte in the target buffer. bytes will be filled
#         starting with this address and proceeding lower until the number
#         runs out.
#
# Returns:
# rax:    address of the first byte in the target string that
#         contains valid information.
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
    dec  %rsi
    add  $0x30, %dl
    movb %dl, (%rsi)

    cmp $0, %rax            # We're done when the quotient is 0.
    jne .L_next_digit

    # If we marked in r9 that the input is negative, it's time to add that
    # '-' in front of the output.
    cmp  $1, %r9
    jne  .L_itoa_done
    dec  %rsi
    movb $0x2d, (%rsi)

.L_itoa_done:
    mov %rsi, %rax          # rsi points to the first byte now; return it.
    ret
