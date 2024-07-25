CPPFLAGS=$(shell sdl2-config --cflags)
ZIGFLAGS=
LDFLAGS=
LDLIBS=-lpthread -lm -ldl $(shell sdl2-config --libs)
BUILDDIR=.zig-cache/precompiled

$(shell mkdir -p $(BUILDDIR))
		
all: rhythmicZig

miniaudio.o:
	gcc $(CPPFLAGS) -include miniaudio/extras/stb_vorbis.c -c miniaudio/extras/miniaudio_split/miniaudio.c -o $(BUILDDIR)/miniaudio.o

rhythmicZig: miniaudio.o
	zig build $(ZIGFLAGS)
