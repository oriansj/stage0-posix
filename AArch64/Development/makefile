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

PATH := ../../mescc-tools/bin:$(PATH)

VPATH = bin-M1:bin-hex2

bin-M1:
	mkdir -p bin-M1

bin-hex2:
	mkdir -p bin-hex2

bin-M1/hex0: hex0_AArch64.M1 | bin-M1
	M1 -f hex0_AArch64.M1 --little-endian --architecture aarch64 -o hold
	catm tmp elf.hex2 hold
	hex2 -f tmp --base-address 0x600000 --little-endian --architecture aarch64 -o bin-M1/hex0

bin-hex2/hex0: hex0_AArch64.hex2 | bin-hex2
	hex2 -f hex0_AArch64.hex2 --base-address 0x600000 --little-endian --architecture aarch64 -o bin-hex2/hex0

all: bin-M1/hex0 bin-hex2/hex0

test: all
	cd bin-M1; sha256sum -c ../../SHA256SUMS --ignore-missing
	cd bin-hex2; sha256sum -c ../../SHA256SUMS --ignore-missing

clean:
	rm -rf bin-M1 bin-hex2 tmp hold
