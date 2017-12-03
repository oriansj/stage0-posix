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

set -ex
# Sin that needs to be removed
# Current hack to give us a holder for blood-elf.M1
../mes/guile/mescc.scm -c -E -I ../mes/include -o blood-elf.E ../mescc-tools/blood-elf.c
../mes/guile/mescc.scm -c -o blood-elf.M1 blood-elf.E
# Current hack to give us a holder for M1.M1
../mes/guile/mescc.scm -c -E -I ../mes/include -o M1.E ../mescc-tools/M1-macro.c
../mes/guile/mescc.scm -c -o M1.M1 M1.E
# Current hack to give us a holder for hex2.M1
../mes/guile/mescc.scm -c -E -I ../mes/include -o hex2.E ../mescc-tools/hex2_linker.c
../mes/guile/mescc.scm -c -o hex2.M1 hex2.E

#########################################
# Phase-0 Build from external binaries  #
# To be replaced by a trusted path      #
#########################################

# blood-elf-0
# Create proper debug segment
../mescc-tools/bin/blood-elf -f blood-elf.M1 -o blood-elf-footer.M1

# Build
# M1-macro phase
../mescc-tools/bin/M1 \
	--LittleEndian\
	--Architecture=1\
	-f ../mes/stage0/x86.M1\
	-f ../mes/lib/crt1.M1\
	-f ../mes/lib/libc-mes+tcc.M1\
	-f blood-elf.M1\
	-f blood-elf-footer.M1\
	-o blood-elf.hex2
# Hex2-linker phase
../mescc-tools/bin/hex2 \
	--LittleEndian\
	--Architecture=1\
	--BaseAddress=0x1000000\
	-f ../mes/stage0/elf32-header.hex2\
	-f blood-elf.hex2\
	-o blood-elf-0\
	--exec_enable

# Clean up temp files used in build
rm blood-elf.E
rm blood-elf.hex2
rm blood-elf-footer.M1

# M1-0
# Create proper debug segment
../mescc-tools/bin/blood-elf -f M1.M1 -o M1-footer.M1

# Build
# M1-macro phase
../mescc-tools/bin/M1 \
	--LittleEndian\
	--Architecture=1\
	-f ../mes/stage0/x86.M1\
	-f ../mes/lib/crt1.M1\
	-f ../mes/lib/libc-mes+tcc.M1\
	-f M1.M1\
	-f M1-footer.M1\
	-o M1.hex2
# Hex2-linker phase
../mescc-tools/bin/hex2 \
	--LittleEndian\
	--Architecture=1\
	--BaseAddress=0x1000000\
	-f ../mes/stage0/elf32-header.hex2\
	-f M1.hex2\
	-f ../mes/stage0/elf32-footer-single-main.hex2\
	-o M1-0\
	--exec_enable

# Clean up temp files used in build
rm M1.E
rm M1.hex2
rm M1-footer.M1

# hex2-0
# Create proper debug segment
../mescc-tools/bin/blood-elf -f hex2.M1 -o hex2-footer.M1

# Build
# M1-macro phase
../mescc-tools/bin/M1 \
	--LittleEndian\
	--Architecture=1\
	-f ../mes/stage0/x86.M1\
	-f ../mes/lib/crt1.M1\
	-f ../mes/lib/libc-mes+tcc.M1\
	-f ../mes/lib/libc-mes+tcc.M1\
	-f hex2.M1\
	-f hex2-footer.M1\
	-o hex2.hex2
# Hex2-linker phase
../mescc-tools/bin/hex2 \
	--LittleEndian\
	--Architecture=1\
	--BaseAddress=0x1000000\
	-f ../mes/stage0/elf32-header.hex2\
	-f hex2.hex2\
	-o hex2-0\
	--exec_enable

# Clean up temp files used in build
rm hex2.E
rm hex2.hex2
rm hex2-footer.M1


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
	-f ../mes/stage0/x86.M1\
	-f ../mes/lib/crt1.M1\
	-f ../mes/lib/libc-mes+tcc.M1\
	-f blood-elf.M1\
	-f blood-elf-footer.M1\
	-o blood-elf.hex2
# Hex2-linker phase
./hex2-0 \
	--LittleEndian\
	--Architecture=1\
	--BaseAddress=0x1000000\
	-f ../mes/stage0/elf32-header.hex2\
	-f blood-elf.hex2\
	-o blood-elf\
	--exec_enable

# Clean up temp files used in build
rm blood-elf.hex2
rm blood-elf-footer.M1

# M1
# Create proper debug segment
./blood-elf-0 -f M1.M1 -o M1-footer.M1

# Build
# M1-macro phase
./M1-0 \
	--LittleEndian\
	--Architecture=1\
	-f ../mes/stage0/x86.M1\
	-f ../mes/lib/crt1.M1\
	-f ../mes/lib/libc-mes+tcc.M1\
	-f M1.M1\
	-f M1-footer.M1\
	-o M1.hex2
# Hex2-linker phase
./hex2-0 \
	--LittleEndian\
	--Architecture=1\
	--BaseAddress=0x1000000\
	-f ../mes/stage0/elf32-header.hex2\
	-f M1.hex2\
	-f ../mes/stage0/elf32-footer-single-main.hex2\
	-o M1\
	--exec_enable

# Clean up temp files used in build
rm M1.hex2
rm M1-footer.M1

# hex2
# Create proper debug segment
./blood-elf-0 -f hex2.M1 -o hex2-footer.M1

# Build
# M1-macro phase
./M1-0 \
	--LittleEndian\
	--Architecture=1\
	-f ../mes/stage0/x86.M1\
	-f ../mes/lib/crt1.M1\
	-f ../mes/lib/libc-mes+tcc.M1\
	-f ../mes/lib/libc-mes+tcc.M1\
	-f hex2.M1\
	-f hex2-footer.M1\
	-o hex2.hex2
# Hex2-linker phase
./hex2-0 \
	--LittleEndian\
	--Architecture=1\
	--BaseAddress=0x1000000\
	-f ../mes/stage0/elf32-header.hex2\
	-f hex2.hex2\
	-o hex2\
	--exec_enable

# Clean up temp files used in build
rm hex2.hex2
rm hex2-footer.M1

#########################################
# Phase-2 Check for unmatched output    #
#########################################

# Check blood-elf
diff -a blood-elf blood-elf-0 || echo "blood elf MISMATCH"
diff -a M1 M1-0 || echo "M1 MISMATCH"
diff -a hex2 hex2-0 || echo "hex2 MISMATCH"
