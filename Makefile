CXXFLAGS::=$(shell sdl2-config --cflags)
ZIGFLAGS::=
LDFLAGS::=
LDLIBS::=-lpthread -lm -ldl $(shell sdl2-config --libs)
BUILDDIR?=.zig-cache/precompiled
CC?=zig cc

$(shell mkdir -p $(BUILDDIR))
		
all:
	$(CC) $(CXXFLAGS) -include src/stb_vorbis_fix.h -c miniaudio/extras/miniaudio_split/miniaudio.c -o $(BUILDDIR)/miniaudio.o
	zig build $(ZIGFLAGS)
