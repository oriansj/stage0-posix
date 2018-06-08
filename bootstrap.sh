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
LIB_PREFIX=${LIB_PREFIX-./libs}
M2_Planet_PREFIX=${M2_Planet_PREFIX-../M2-Planet}
MESCC_TOOLS_PREFIX=${MESCC_TOOLS_PREFIX-../mescc-tools}

# Sin that needs to be removed
# Current hack to give us a holder for blood-elf.M1
# To execute this block ./bootstrap.sh sin
if [ "sin" = "${1-NOPE}" ]
then
	# First build the libraries
	$M2_Planet_PREFIX/bin/M2-Planet -f $M2_Planet_PREFIX/test/functions/exit.c | head -n-7 >| libs/exit.M1
	$M2_Planet_PREFIX/bin/M2-Planet -f $M2_Planet_PREFIX/test/functions/file.c | head -n-7 >| libs/file.M1
	$M2_Planet_PREFIX/bin/M2-Planet -f $M2_Planet_PREFIX/test/functions/file_print.c | head -n-7 >| libs/file_print.M1
	$M2_Planet_PREFIX/bin/M2-Planet -f $M2_Planet_PREFIX/test/functions/malloc.c | head -n-7 >| libs/malloc.M1
	$M2_Planet_PREFIX/bin/M2-Planet -f $M2_Planet_PREFIX/test/functions/calloc.c | head -n-7 >| libs/calloc.M1
	$M2_Planet_PREFIX/bin/M2-Planet -f $M2_Planet_PREFIX/test/functions/match.c | head -n-7 >| libs/match.M1
	$M2_Planet_PREFIX/bin/M2-Planet -f $M2_Planet_PREFIX/test/functions/numerate_number.c | head -n-7 >| libs/numerate_number.M1
	$M2_Planet_PREFIX/bin/M2-Planet -f $M2_Planet_PREFIX/test/functions/string.c | head -n-7 >| libs/string.M1
	$M2_Planet_PREFIX/bin/M2-Planet -f $M2_Planet_PREFIX/test/functions/stat.c | head -n-7 >| libs/stat.M1

	# Build the core programs
	$M2_Planet_PREFIX/bin/M2-Planet --debug \
		-f $M2_Planet_PREFIX/test/test23/stub.h \
		-f $M2_Planet_PREFIX/test/test23/M1-macro.c \
		-o M1.M1
	$M2_Planet_PREFIX/bin/M2-Planet --debug \
		-f $M2_Planet_PREFIX/test/test22/stub.h \
		-f $M2_Planet_PREFIX/test/test22/hex2_linker.c \
		-o hex2.M1
	$M2_Planet_PREFIX/bin/M2-Planet --debug \
		-f $M2_Planet_PREFIX/test/test21/stub.h \
		-f $M2_Planet_PREFIX/test/test21/blood-elf.c \
		-o blood-elf.M1
fi

#########################################
# Phase-0 Build from external binaries  #
# To be replaced by a trusted path      #
#########################################

# blood-elf-0
# Create proper debug segment
$MESCC_TOOLS_PREFIX/bin/blood-elf \
	-f $LIB_PREFIX/exit.M1 \
	-f $LIB_PREFIX/file.M1 \
	-f $LIB_PREFIX/file_print.M1 \
	-f $LIB_PREFIX/malloc.M1 \
	-f $LIB_PREFIX/calloc.M1 \
	-f $LIB_PREFIX/match.M1 \
	-f blood-elf.M1\
	-o blood-elf-footer.M1

# Build
# M1-macro phase
$MESCC_TOOLS_PREFIX/bin/M1 \
	--LittleEndian\
	--Architecture 1\
	-f $LIB_PREFIX/x86_defs.M1\
	-f $LIB_PREFIX/libc-core.M1\
	-f $LIB_PREFIX/exit.M1 \
	-f $LIB_PREFIX/file.M1 \
	-f $LIB_PREFIX/file_print.M1 \
	-f $LIB_PREFIX/malloc.M1 \
	-f $LIB_PREFIX/calloc.M1 \
	-f $LIB_PREFIX/match.M1 \
	-f blood-elf.M1\
	-f blood-elf-footer.M1\
	-o blood-elf.hex2

# Hex2-linker phase
$MESCC_TOOLS_PREFIX/bin/hex2 \
	--LittleEndian\
	--Architecture 1\
	--BaseAddress 0x8048000\
	-f $LIB_PREFIX/ELF-i386-debug.hex2\
	-f blood-elf.hex2\
	-o blood-elf-0\
	--exec_enable

# Clean up temp files used in build
[ -f blood-elf.E ] && rm blood-elf.E
[ -f blood-elf.hex2 ] && rm blood-elf.hex2
[ -f blood-elf-footer.M1 ] && rm blood-elf-footer.M1

# M1-0
# Create proper debug segment
$MESCC_TOOLS_PREFIX/bin/blood-elf \
	-f $LIB_PREFIX/exit.M1 \
	-f $LIB_PREFIX/file.M1 \
	-f $LIB_PREFIX/file_print.M1 \
	-f $LIB_PREFIX/malloc.M1 \
	-f $LIB_PREFIX/calloc.M1 \
	-f $LIB_PREFIX/match.M1 \
	-f $LIB_PREFIX/numerate_number.M1 \
	-f $LIB_PREFIX/string.M1 \
	-f M1.M1\
	-o M1-footer.M1

# Build
# M1-macro phase
$MESCC_TOOLS_PREFIX/bin/M1 \
	--LittleEndian\
	--Architecture 1\
	-f $LIB_PREFIX/x86_defs.M1\
	-f $LIB_PREFIX/libc-core.M1\
	-f $LIB_PREFIX/exit.M1 \
	-f $LIB_PREFIX/file.M1 \
	-f $LIB_PREFIX/file_print.M1 \
	-f $LIB_PREFIX/malloc.M1 \
	-f $LIB_PREFIX/calloc.M1 \
	-f $LIB_PREFIX/match.M1 \
	-f $LIB_PREFIX/numerate_number.M1 \
	-f $LIB_PREFIX/string.M1 \
	-f M1.M1\
	-f M1-footer.M1\
	-o M1.hex2

# Hex2-linker phase
$MESCC_TOOLS_PREFIX/bin/hex2 \
	--LittleEndian\
	--Architecture 1\
	--BaseAddress 0x8048000\
	-f $LIB_PREFIX/ELF-i386-debug.hex2\
	-f M1.hex2\
	-o M1-0\
	--exec_enable

# Clean up temp files used in build
[ -f M1.E ] && rm M1.E
[ -f M1.hex2 ] && rm M1.hex2
[ -f M1-footer.M1 ] && rm M1-footer.M1

# hex2-0
# Create proper debug segment
$MESCC_TOOLS_PREFIX/bin/blood-elf \
	-f $LIB_PREFIX/exit.M1 \
	-f $LIB_PREFIX/file.M1 \
	-f $LIB_PREFIX/file_print.M1 \
	-f $LIB_PREFIX/malloc.M1 \
	-f $LIB_PREFIX/calloc.M1 \
	-f $LIB_PREFIX/match.M1 \
	-f $LIB_PREFIX/numerate_number.M1 \
	-f $LIB_PREFIX/stat.M1 \
	-f hex2.M1\
	-o hex2-footer.M1

# Build
# M1-macro phase
$MESCC_TOOLS_PREFIX/bin/M1 \
	--LittleEndian\
	--Architecture 1\
	-f $LIB_PREFIX/x86_defs.M1\
	-f $LIB_PREFIX/libc-core.M1\
	-f $LIB_PREFIX/exit.M1 \
	-f $LIB_PREFIX/file.M1 \
	-f $LIB_PREFIX/file_print.M1 \
	-f $LIB_PREFIX/malloc.M1 \
	-f $LIB_PREFIX/calloc.M1 \
	-f $LIB_PREFIX/match.M1 \
	-f $LIB_PREFIX/numerate_number.M1 \
	-f $LIB_PREFIX/stat.M1 \
	-f hex2.M1\
	-f hex2-footer.M1\
	-o hex2.hex2

# Hex2-linker phase
$MESCC_TOOLS_PREFIX/bin/hex2 \
	--LittleEndian\
	--Architecture 1\
	--BaseAddress 0x8048000\
	-f $LIB_PREFIX/ELF-i386-debug.hex2\
	-f hex2.hex2\
	-o hex2-0\
	--exec_enable

# Clean up temp files used in build
[ -f hex2.E ] && rm hex2.E
[ -f hex2.hex2 ] && rm hex2.hex2
[ -f hex2-footer.M1 ] && rm hex2-footer.M1


#############################################
# Phase-1 Build from bootstrapped binaries  #
#############################################

# blood-elf
# Create proper debug segment
./blood-elf-0 -f $LIB_PREFIX/exit.M1 \
	-f $LIB_PREFIX/file.M1 \
	-f $LIB_PREFIX/file_print.M1 \
	-f $LIB_PREFIX/malloc.M1 \
	-f $LIB_PREFIX/calloc.M1 \
	-f $LIB_PREFIX/match.M1 \
	-f blood-elf.M1\
	-o blood-elf-footer.M1

# Build
# M1-macro phase
./M1-0 \
	--LittleEndian\
	--Architecture 1\
	-f $LIB_PREFIX/x86_defs.M1\
	-f $LIB_PREFIX/libc-core.M1\
	-f $LIB_PREFIX/exit.M1 \
	-f $LIB_PREFIX/file.M1 \
	-f $LIB_PREFIX/file_print.M1 \
	-f $LIB_PREFIX/malloc.M1 \
	-f $LIB_PREFIX/calloc.M1 \
	-f $LIB_PREFIX/match.M1 \
	-f blood-elf.M1\
	-f blood-elf-footer.M1\
	-o blood-elf.hex2

# Hex2-linker phase
./hex2-0 \
	--LittleEndian\
	--Architecture 1\
	--BaseAddress 0x8048000\
	-f $LIB_PREFIX/ELF-i386-debug.hex2\
	-f blood-elf.hex2\
	-o blood-elf\
	--exec_enable

# Clean up temp files used in build
[ -f blood-elf.hex2 ] && rm blood-elf.hex2
[ -f blood-elf-footer.M1 ] && rm blood-elf-footer.M1

# M1
# Create proper debug segment
./blood-elf-0 -f $LIB_PREFIX/exit.M1 \
	-f $LIB_PREFIX/file.M1 \
	-f $LIB_PREFIX/file_print.M1 \
	-f $LIB_PREFIX/malloc.M1 \
	-f $LIB_PREFIX/calloc.M1 \
	-f $LIB_PREFIX/match.M1 \
	-f $LIB_PREFIX/numerate_number.M1 \
	-f $LIB_PREFIX/string.M1 \
	-f M1.M1\
	-o M1-footer.M1

# Build
# M1-macro phase
./M1-0 \
	--LittleEndian\
	--Architecture 1\
	-f $LIB_PREFIX/x86_defs.M1\
	-f $LIB_PREFIX/libc-core.M1\
	-f $LIB_PREFIX/exit.M1 \
	-f $LIB_PREFIX/file.M1 \
	-f $LIB_PREFIX/file_print.M1 \
	-f $LIB_PREFIX/malloc.M1 \
	-f $LIB_PREFIX/calloc.M1 \
	-f $LIB_PREFIX/match.M1 \
	-f $LIB_PREFIX/numerate_number.M1 \
	-f $LIB_PREFIX/string.M1 \
	-f M1.M1\
	-f M1-footer.M1\
	-o M1.hex2
# Hex2-linker phase
./hex2-0 \
	--LittleEndian\
	--Architecture 1\
	--BaseAddress 0x8048000\
	-f $LIB_PREFIX/ELF-i386-debug.hex2\
	-f M1.hex2\
	-o M1\
	--exec_enable

# Clean up temp files used in build
[ -f M1.hex2 ] && rm M1.hex2
[ -f M1-footer.M1 ] && rm M1-footer.M1

# hex2
# Create proper debug segment
./blood-elf-0 -f $LIB_PREFIX/exit.M1 \
	-f $LIB_PREFIX/file.M1 \
	-f $LIB_PREFIX/file_print.M1 \
	-f $LIB_PREFIX/malloc.M1 \
	-f $LIB_PREFIX/calloc.M1 \
	-f $LIB_PREFIX/match.M1 \
	-f $LIB_PREFIX/numerate_number.M1 \
	-f $LIB_PREFIX/stat.M1 \
	-f hex2.M1\
	-o hex2-footer.M1

# Build
# M1-macro phase
./M1-0 \
	--LittleEndian\
	--Architecture 1\
	-f $LIB_PREFIX/x86_defs.M1\
	-f $LIB_PREFIX/libc-core.M1\
	-f $LIB_PREFIX/exit.M1 \
	-f $LIB_PREFIX/file.M1 \
	-f $LIB_PREFIX/file_print.M1 \
	-f $LIB_PREFIX/malloc.M1 \
	-f $LIB_PREFIX/calloc.M1 \
	-f $LIB_PREFIX/match.M1 \
	-f $LIB_PREFIX/numerate_number.M1 \
	-f $LIB_PREFIX/stat.M1 \
	-f hex2.M1\
	-f hex2-footer.M1\
	-o hex2.hex2
# Hex2-linker phase
./hex2-0 \
	--LittleEndian\
	--Architecture 1\
	--BaseAddress 0x8048000\
	-f $LIB_PREFIX/ELF-i386-debug.hex2\
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
[ -f M1-0 ] && rm M1-0
[ -f blood-elf-0 ] && rm blood-elf-0
[ -f hex2-0 ] && rm hex2-0
echo "SUCCESS"
