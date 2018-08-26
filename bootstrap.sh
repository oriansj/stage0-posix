#! /usr/bin/env bash
# Mes --- Maxwell Equations of Software
# Copyright © 2017 Jan Nieuwenhuizen <janneke@gnu.org>
# Copyright © 2017 Jeremiah Orians
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

set -eux
stage0_PREFIX=${stage0_PREFIX-../stage0}

#########################################
# Phase-0 Generate M1 source files from #
# source using cc_x86.s                 #
#########################################

# Generate get_machine.M1
# $stage0_PREFIX/bin/vm --rom $stage0_PREFIX/roms/cc_x86 \
#	--memory 4M \
#	--tape_01 $stage0_PREFIX/stage3/get_machine_x86.c \
#	--tape_02 get_machine.M1

# Generate blood-elf.M1
$stage0_PREFIX/bin/vm --rom $stage0_PREFIX/roms/cc_x86 \
	--memory 4M \
	--tape_01 $stage0_PREFIX/stage3/blood-elf_x86.c \
	--tape_02 blood-elf.M1

# Generate hex2.M1
$stage0_PREFIX/bin/vm --rom $stage0_PREFIX/roms/cc_x86 \
	--memory 4M \
	--tape_01 $stage0_PREFIX/stage3/hex2_linker_x86.c \
	--tape_02 hex2.M1

# Generate M1.M1
$stage0_PREFIX/bin/vm --rom $stage0_PREFIX/roms/cc_x86 \
	--memory 4M \
	--tape_01 $stage0_PREFIX/stage3/M1-macro_x86.c \
	--tape_02 M1.M1


# Sin that needs to be removed
# Current hack generate binary seeds
# To execute this block ./bootstrap.sh sin
if [ "sin" = "${1-NOPE}" ]
then
MESCC_TOOLS_PREFIX=${MESCC_TOOLS_PREFIX-../mescc-tools}

# blood-elf-0
# Create proper debug segment
$MESCC_TOOLS_PREFIX/bin/blood-elf \
	-f blood-elf.M1\
	-o blood-elf-footer.M1

# Build
# M1-macro phase
$MESCC_TOOLS_PREFIX/bin/M1 \
	--LittleEndian\
	--Architecture 1\
	-f x86_defs.M1\
	-f libc-core.M1\
	-f blood-elf.M1\
	-f blood-elf-footer.M1\
	-o blood-elf.hex2

# Hex2-linker phase
$MESCC_TOOLS_PREFIX/bin/hex2 \
	--LittleEndian\
	--Architecture 1\
	--BaseAddress 0x8048000\
	-f ELF-i386-debug.hex2\
	-f blood-elf.hex2\
	-o blood-elf-0\
	--exec_enable

# Clean up temp files used in build
[ -f blood-elf.hex2 ] && rm blood-elf.hex2
[ -f blood-elf-footer.M1 ] && rm blood-elf-footer.M1

# M1-0
# Create proper debug segment
$MESCC_TOOLS_PREFIX/bin/blood-elf \
	-f M1.M1\
	-o M1-footer.M1

# Build
# M1-macro phase
$MESCC_TOOLS_PREFIX/bin/M1 \
	--LittleEndian\
	--Architecture 1\
	-f x86_defs.M1\
	-f libc-core.M1\
	-f M1.M1\
	-f M1-footer.M1\
	-o M1.hex2

# Hex2-linker phase
$MESCC_TOOLS_PREFIX/bin/hex2 \
	--LittleEndian\
	--Architecture 1\
	--BaseAddress 0x8048000\
	-f ELF-i386-debug.hex2\
	-f M1.hex2\
	-o M1-0\
	--exec_enable

# Clean up temp files used in build
[ -f M1.hex2 ] && rm M1.hex2
[ -f M1-footer.M1 ] && rm M1-footer.M1

# hex2-0
# Create proper debug segment
$MESCC_TOOLS_PREFIX/bin/blood-elf \
	-f hex2.M1\
	-o hex2-footer.M1

# Build
# M1-macro phase
$MESCC_TOOLS_PREFIX/bin/M1 \
	--LittleEndian\
	--Architecture 1\
	-f x86_defs.M1\
	-f libc-core.M1\
	-f hex2.M1\
	-f hex2-footer.M1\
	-o hex2.hex2

# Hex2-linker phase
$MESCC_TOOLS_PREFIX/bin/hex2 \
	--LittleEndian\
	--Architecture 1\
	--BaseAddress 0x8048000\
	-f ELF-i386-debug.hex2\
	-f hex2.hex2\
	-o hex2-0\
	--exec_enable

# Clean up temp files used in build
[ -f hex2.hex2 ] && rm hex2.hex2
[ -f hex2-footer.M1 ] && rm hex2-footer.M1

fi


#############################################
# Phase-1 Build from bootstrapped binaries  #
#############################################

# blood-elf
# Create proper debug segment
./blood-elf-0 -f blood-elf.M1\
	-o blood-elf-footer.M1

# Build
# M1-macro phase
./M1-0  --LittleEndian\
	--Architecture 1\
	-f x86_defs.M1\
	-f libc-core.M1\
	-f blood-elf.M1\
	-f blood-elf-footer.M1\
	-o blood-elf.hex2

# Hex2-linker phase
./hex2-0 --LittleEndian\
	--Architecture 1\
	--BaseAddress 0x8048000\
	-f ELF-i386-debug.hex2\
	-f blood-elf.hex2\
	-o blood-elf\
	--exec_enable

# Clean up temp files used in build
[ -f blood-elf.hex2 ] && rm blood-elf.hex2
[ -f blood-elf-footer.M1 ] && rm blood-elf-footer.M1

# M1
# Create proper debug segment
./blood-elf-0 -f M1.M1\
	-o M1-footer.M1

# Build
# M1-macro phase
./M1-0 	--LittleEndian\
	--Architecture 1\
	-f x86_defs.M1\
	-f libc-core.M1\
	-f M1.M1\
	-f M1-footer.M1\
	-o M1.hex2

# Hex2-linker phase
./hex2-0 --LittleEndian\
	--Architecture 1\
	--BaseAddress 0x8048000\
	-f ELF-i386-debug.hex2\
	-f M1.hex2\
	-o M1\
	--exec_enable

# Clean up temp files used in build
[ -f M1.hex2 ] && rm M1.hex2
[ -f M1-footer.M1 ] && rm M1-footer.M1

# hex2
# Create proper debug segment
./blood-elf-0 -f hex2.M1\
	-o hex2-footer.M1

# Build
# M1-macro phase
./M1-0 	--LittleEndian\
	--Architecture 1\
	-f x86_defs.M1\
	-f libc-core.M1\
	-f hex2.M1\
	-f hex2-footer.M1\
	-o hex2.hex2

# Hex2-linker phase
./hex2-0 --LittleEndian\
	--Architecture 1\
	--BaseAddress 0x8048000\
	-f ELF-i386-debug.hex2\
	-f hex2.hex2\
	-o hex2\
	--exec_enable

# Clean up temp files used in build
[ -f hex2.hex2 ] && rm hex2.hex2
[ -f hex2-footer.M1 ] && rm hex2-footer.M1

#########################################
# Phase-2 Check for unmatched output    #
#########################################

# Check blood-elf
diff -a blood-elf blood-elf-0 || echo "blood elf MISMATCH"
# Check M1
diff -a M1 M1-0 || echo "M1 MISMATCH"
# Check hex2
diff -a hex2 hex2-0 || echo "hex2 MISMATCH"

#########################################
# Phase-3 Clean up files being tested   #
#########################################
# [ -f M1-0 ] && rm M1-0
# [ -f blood-elf-0 ] && rm blood-elf-0
# [ -f hex2-0 ] && rm hex2-0
echo "SUCCESS"
