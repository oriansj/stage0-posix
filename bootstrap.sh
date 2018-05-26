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
MES_PREFIX=${MES_PREFIX-../mes}
MESCC_TOOLS_PREFIX=${MESCC_TOOLS_PREFIX-../mescc-tools}

# Sin that needs to be removed
# Current hack to give us a holder for blood-elf.M1
# To execute this block ./bootstrap.sh sin
if [ "sin" = "${1-NOPE}" ]
then
	$MES_PREFIX/guile/mescc.scm -c -E -I $MES_PREFIX/include -o blood-elf.E $MESCC_TOOLS_PREFIX/blood-elf.c
	$MES_PREFIX/guile/mescc.scm -c -o blood-elf.M1 blood-elf.E
	# Current hack to give us a holder for M1.M1
	$MES_PREFIX/guile/mescc.scm -c -E -I $MES_PREFIX/include -o M1.E $MESCC_TOOLS_PREFIX/M1-macro.c
	$MES_PREFIX/guile/mescc.scm -c -o M1.M1 M1.E
	# Current hack to give us a holder for hex2.M1
	$MES_PREFIX/guile/mescc.scm -c -E -I $MES_PREFIX/include -o hex2.E $MESCC_TOOLS_PREFIX/hex2_linker.c
	$MES_PREFIX/guile/mescc.scm -c -o hex2.M1 hex2.E
fi

#########################################
# Phase-0 Build from external binaries  #
# To be replaced by a trusted path      #
#########################################

# blood-elf-0
# Create proper debug segment
$MESCC_TOOLS_PREFIX/bin/blood-elf \
	-f blood-elf.M1\
	-o blood-elf-footer.M1

# Build
# M1-macro phase
$MESCC_TOOLS_PREFIX/bin/M1 \
	--LittleEndian\
	--Architecture=1\
	-f $LIB_PREFIX/x86.M1\
	-f $LIB_PREFIX/crt1.M1\
	-f $LIB_PREFIX/libc+tcc-mes.M1\
	-f blood-elf.M1\
	-f blood-elf-footer.M1\
	-o blood-elf.hex2

# Hex2-linker phase
$MESCC_TOOLS_PREFIX/bin/hex2 \
	--LittleEndian\
	--Architecture=1\
	--BaseAddress=0x1000000\
	-f $LIB_PREFIX/elf32-header.hex2\
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
	-f M1.M1 \
	-o M1-footer.M1

# Build
# M1-macro phase
$MESCC_TOOLS_PREFIX/bin/M1 \
	--LittleEndian\
	--Architecture=1\
	-f $LIB_PREFIX/x86.M1\
	-f $LIB_PREFIX/crt1.M1\
	-f $LIB_PREFIX/libc+tcc-mes.M1\
	-f M1.M1\
	-f M1-footer.M1\
	-o M1.hex2

# Hex2-linker phase
$MESCC_TOOLS_PREFIX/bin/hex2 \
	--LittleEndian\
	--Architecture=1\
	--BaseAddress=0x1000000\
	-f $LIB_PREFIX/elf32-header.hex2\
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
	-f hex2.M1\
	-o hex2-footer.M1

# Build
# M1-macro phase
$MESCC_TOOLS_PREFIX/bin/M1 \
	--LittleEndian\
	--Architecture=1\
	-f $LIB_PREFIX/x86.M1\
	-f $LIB_PREFIX/crt1.M1\
	-f $LIB_PREFIX/libc+tcc-mes.M1\
	-f hex2.M1\
	-f hex2-footer.M1\
	-o hex2.hex2

# Hex2-linker phase
$MESCC_TOOLS_PREFIX/bin/hex2 \
	--LittleEndian\
	--Architecture=1\
	--BaseAddress=0x1000000\
	-f $LIB_PREFIX/elf32-header.hex2\
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
./blood-elf-0 -f blood-elf.M1 -o blood-elf-footer.M1

# Build
# M1-macro phase
./M1-0 \
	--LittleEndian\
	--Architecture=1\
	-f $LIB_PREFIX/x86.M1\
	-f $LIB_PREFIX/crt1.M1\
	-f $LIB_PREFIX/libc+tcc-mes.M1\
	-f blood-elf.M1\
	-f blood-elf-footer.M1\
	-o blood-elf.hex2

# Hex2-linker phase
./hex2-0 \
	--LittleEndian\
	--Architecture=1\
	--BaseAddress=0x1000000\
	-f $LIB_PREFIX/elf32-header.hex2\
	-f blood-elf.hex2\
	-o blood-elf\
	--exec_enable

# Clean up temp files used in build
[ -f blood-elf.hex2 ] && rm blood-elf.hex2
[ -f blood-elf-footer.M1 ] && rm blood-elf-footer.M1

# M1
# Create proper debug segment
./blood-elf-0 -f M1.M1 -o M1-footer.M1

# Build
# M1-macro phase
./M1-0 \
	--LittleEndian\
	--Architecture=1\
	-f $LIB_PREFIX/x86.M1\
	-f $LIB_PREFIX/crt1.M1\
	-f $LIB_PREFIX/libc+tcc-mes.M1\
	-f M1.M1\
	-f M1-footer.M1\
	-o M1.hex2
# Hex2-linker phase
./hex2-0 \
	--LittleEndian\
	--Architecture=1\
	--BaseAddress=0x1000000\
	-f $LIB_PREFIX/elf32-header.hex2\
	-f M1.hex2\
	-o M1\
	--exec_enable

# Clean up temp files used in build
[ -f M1.hex2 ] && rm M1.hex2
[ -f M1-footer.M1 ] && rm M1-footer.M1

# hex2
# Create proper debug segment
./blood-elf-0 -f hex2.M1 -o hex2-footer.M1

# Build
# M1-macro phase
./M1-0 \
	--LittleEndian\
	--Architecture=1\
	-f $LIB_PREFIX/x86.M1\
	-f $LIB_PREFIX/crt1.M1\
	-f $LIB_PREFIX/libc+tcc-mes.M1\
	-f hex2.M1\
	-f hex2-footer.M1\
	-o hex2.hex2
# Hex2-linker phase
./hex2-0 \
	--LittleEndian\
	--Architecture=1\
	--BaseAddress=0x1000000\
	-f $LIB_PREFIX/elf32-header.hex2\
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
