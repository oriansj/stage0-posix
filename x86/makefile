# Mes --- Maxwell Equations of Software
# Copyright © 2020 Jeremiah Orians
#
# This file is part of Mes.
#
# Mes is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or (at
# your option) any later version.
#
# Mes is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Mes.  If not, see <http://www.gnu.org/licenses/>.

VPATH = bin

# Directories
bin:
	mkdir -p bin

# make the NASM pieces
hex0-nasm: NASM/hex0_x86.S | bin
	nasm -felf32 NASM/hex0_x86.S -o bin/hex0.o
	ld -melf_i386 bin/hex0.o -o bin/hex0-nasm

hex1-nasm: NASM/hex1_x86.S | bin
	nasm -felf32 NASM/hex1_x86.S -o bin/hex1.o
	ld -melf_i386 bin/hex1.o -o bin/hex1-nasm

catm-nasm: NASM/catm_x86.S | bin
	nasm -felf32 NASM/catm_x86.S -o bin/catm.o
	ld -melf_i386 bin/catm.o -o bin/catm-nasm

hex2-nasm: NASM/hex2_x86.S | bin
	nasm -felf32 NASM/hex2_x86.S -o bin/hex2.o
	ld -melf_i386 bin/hex2.o -o bin/hex2-nasm

M0-nasm: NASM/M0_x86.S | bin
	nasm -felf32 NASM/M0_x86.S -o bin/M0.o
	ld -melf_i386 bin/M0.o -o bin/M0-nasm

cc_x86-nasm: NASM/cc_x86.S | bin
	nasm -felf32 NASM/cc_x86.S -o bin/cc_x86.o
	ld -melf_i386 bin/cc_x86.o -o bin/cc_x86-nasm

kaem-nasm: NASM/kaem-minimal.S | bin
	nasm -felf32 NASM/kaem-minimal.S -o bin/kaem.o
	ld -melf_i386 bin/kaem.o -o bin/kaem-nasm

# make pieces from the NASM pieces
hex0: hex0-nasm
	./bin/hex0-nasm hex0_x86.hex0 hex0

kaem-0: hex0-nasm
	./bin/hex0-nasm kaem-minimal.hex0 kaem-0

hex1: hex0-nasm
	./bin/hex0-nasm hex1_x86.hex0 hex1

catm: hex0-nasm
	./bin/hex0-nasm catm_x86.hex0 catm

hex2-0: hex1-nasm
	./bin/hex1-nasm hex2_x86.hex1 hex2-0

M0: hex2-nasm catm-nasm
	./bin/catm-nasm hold ELF-i386.hex2 M0_x86.hex2
	./bin/hex2-nasm hold M0

cc_x86: hex2-nasm catm-nasm M0-nasm
	./bin/M0-nasm cc_x86.M1 temp1
	./bin/catm-nasm hold ELF-i386.hex2 temp1
	./bin/hex2-nasm hold cc_x86

M2: hex2-nasm catm-nasm M0-nasm cc_x86-nasm
	./bin/catm-nasm hold ../M2-Planet/test/common_x86/functions/file.c ../M2-Planet/test/common_x86/functions/malloc.c ../M2-Planet/functions/calloc.c ../M2-Planet/test/common_x86/functions/exit.c ../M2-Planet/functions/match.c ../M2-Planet/functions/in_set.c ../M2-Planet/functions/numerate_number.c ../M2-Planet/functions/file_print.c ../M2-Planet/functions/number_pack.c ../M2-Planet/functions/string.c ../M2-Planet/functions/require.c ../M2-Planet/functions/fixup.c ../M2-Planet/cc.h ../M2-Planet/cc_globals.c ../M2-Planet/cc_reader.c ../M2-Planet/cc_strings.c ../M2-Planet/cc_types.c ../M2-Planet/cc_core.c ../M2-Planet/cc.c
	./bin/cc_x86-nasm hold M2.M1
	./bin/catm-nasm hold x86_defs.M1 libc-core.M1 M2.M1
	./bin/M0-nasm hold temp1
	./bin/catm-nasm hold ELF-i386.hex2 temp1
	./bin/hex2-nasm hold M2

all: M2 cc_x86 M0 hex2-0 catm hex1 hex0 kaem-0

test: all
	sha256sum -c SHA256SUMS

Generate_test_answers: all
	sha256sum catm cc_x86 hex0 hex1 hex2-0 kaem-0 M0 M2 >| SHA256SUMS
