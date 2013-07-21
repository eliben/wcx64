AS = as
ASFLAGS = --64
LD = ld
LDFLAGS =

all: 	wcx64

wcx64: wcx64.o
	$(LD) $(LDFLAGS) -o $@ $<

%.o: %.s
	$(AS) $(ASFLAGS) $< -o $@

clean:
	rm -f *.o wcx64 a.out
