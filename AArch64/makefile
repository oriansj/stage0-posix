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

kaem-gas: GAS/kaem-minimal.S | bin
	as GAS/kaem-minimal.S -o bin/kaem.o
	ld bin/kaem.o -o bin/kaem-gas
