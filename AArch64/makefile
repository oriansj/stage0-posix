# Copyright © 2020 Jeremiah Orians
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

VPATH = bin

# Directories
bin:
	mkdir -p bin

# make the GAS pieces
bin/hex0-gas: GAS/hex0_AArch64.S | bin
	as GAS/hex0_AArch64.S -o bin/hex0.o
	ld bin/hex0.o -o bin/hex0-gas

bin/hex1-gas: GAS/hex1_AArch64.S | bin
	as GAS/hex1_AArch64.S -o bin/hex1.o
	ld bin/hex1.o -o bin/hex1-gas

bin/catm-gas: GAS/catm_AArch64.S | bin
	as GAS/catm_AArch64.S -o bin/catm.o
	ld bin/catm.o -o bin/catm-gas

bin/hex2-gas: GAS/hex2_AArch64.S | bin
	as GAS/hex2_AArch64.S -o bin/hex2.o
	ld bin/hex2.o -o bin/hex2-gas

bin/M0-gas: GAS/M0_AArch64.S | bin
	as GAS/M0_AArch64.S -o bin/M0.o
	ld bin/M0.o -o bin/M0-gas

bin/cc_aarch64-gas: GAS/cc_aarch64.S | bin
	as GAS/cc_aarch64.S -o bin/cc_aarch64.o
	ld bin/cc_aarch64.o -o bin/cc_aarch64-gas

# make pieces from the GAS pieces
hex0: hex0-gas
	./bin/hex0-gas hex0_AArch64.hex0 hex0

hex1: hex0-gas
	./bin/hex0-gas hex1_AArch64.hex0 hex1

catm: hex1-gas
	./bin/hex1-gas catm_AArch64.hex1 catm

hex2-0: hex1-gas
	./bin/hex1-gas hex2_AArch64.hex1 hex2-0

M0: hex2-gas catm-gas
	./bin/catm-gas hold ELF-aarch64.hex2 M0_AArch64.hex2
	./bin/hex2-gas hold M0

cc_aarch64: hex2-gas M0-gas catm-gas
	./bin/M0-gas cc_aarch64.M1 temp1
	./bin/catm-gas hold ELF-aarch64.hex2 temp1
	./bin/hex2-gas hold cc_aarch64

all: hex0 hex1 catm hex2-0 M0 cc_aarch64

clean:
	rm -f hex0 hex1 catm hex2-0 M0 cc_aarch64
	rm -rf bin

test: all
	sha256sum -c SHA256SUMS

Generate_test_answers: all
	sha256sum hex0 hex1 catm hex2-0 M0 cc_aarch64 >| SHA256SUMS
