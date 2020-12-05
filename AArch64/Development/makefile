# Copyright © 2020 Sanne Wouda
# This file is part of stage0.
#
# stage0 is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# stage0 is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with stage0.  If not, see <http://www.gnu.org/licenses/>.

VPATH = ../../bin

bin:
	mkdir -p ../../bin

M1-hex0: hex0_AArch64.M1 | bin
	M1 -f hex0_AArch64.M1 --little-endian --architecture aarch64 -o hold
	hex2 -f elf.hex2 -f hold --base-address 0x600000 --little-endian --architecture aarch64 -o ../../bin/M1-hex0

hex2-hex0: hex0_AArch64.hex2 | bin
	hex2 -f hex0_AArch64.hex2 --base-address 0x600000 --little-endian --architecture aarch64 -o ../../bin/hex2-hex0

# hex0 does not depend upon any labels or offsets and thus does not need base-address endianness or even architecture.
# As it must always have exactly one output regardless of host or target.
hex0-hex0: ../hex0_AArch64.hex0 | bin
	hex2 -f ../hex0_AArch64.hex0 -o ../../bin/hex0-hex0

M1-hex1: hex1_AArch64.M1 | bin
	M1 -f hex1_AArch64.M1 --little-endian --architecture aarch64 -o hold
	hex2 -f elf.hex2 -f hold --base-address 0x600000 --little-endian --architecture aarch64 -o ../../bin/M1-hex1

hex2-hex1: hex1_AArch64.hex2 | bin
	hex2 -f hex1_AArch64.hex2 --base-address 0x600000 --little-endian --architecture aarch64 -o ../../bin/hex2-hex1

hex0-hex1: ../hex1_AArch64.hex0 | bin
	hex2 -f ../hex1_AArch64.hex0 -o ../../bin/hex0-hex1

all: M1-hex0 hex2-hex0 hex0-hex0 M1-hex1 hex2-hex1 hex0-hex1

test: all
	sha256sum -c SHA256SUMS

clean:
	rm -f hold \
		../../bin/hex0-hex0 ../../bin/hex2-hex0 ../../bin/M1-hex0 \
		../../bin/hex0-hex1 ../../bin/hex2-hex1 ../../bin/M1-hex1

Generate_test_answers: all
	sha256sum ../../bin/*-hex0 ../../bin/*-hex1 >| SHA256SUMS
