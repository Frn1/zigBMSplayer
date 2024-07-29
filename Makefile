CXXFLAGS::=
ZIGFLAGS::=
BUILDDIR?=.zig-cache/precompiled
CC?=zig cc

$(shell mkdir -p $(BUILDDIR))

.PHONY: miniaudio

miniaudio:
	$(CC) $(CXXFLAGS) -fno-sanitize=undefined -include src/stb_vorbis_fix.h -c miniaudio/extras/miniaudio_split/miniaudio.c -o $(BUILDDIR)/miniaudio.o

all: 	
	zig build $(ZIGFLAGS)
