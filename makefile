# Mes --- Maxwell Equations of Software
# Copyright © 2017 Jeremiah Orians
# Copyright © 2017 Jan Nieuwenhuizen <janneke@gnu.org>
# Copyright © 2020 Sanne Wouda
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

PACKAGE = stage0-posix

Generate-x86-answers:
	sha256sum x86/bin/blood-elf \
x86/bin/catm \
x86/bin/chmod \
x86/bin/cp \
x86/bin/get_machine \
x86/bin/hex2 \
x86/bin/kaem \
x86/bin/M1 \
x86/bin/M2-Mesoplanet \
x86/bin/M2-Planet \
x86/bin/match \
x86/bin/mkdir \
x86/bin/replace \
x86/bin/rm \
x86/bin/sha256sum \
x86/bin/ungz \
x86/bin/unbz2 \
x86/bin/unxz \
x86/bin/untar >| x86.answers

Generate-amd64-answers:
	sha256sum AMD64/bin/blood-elf \
AMD64/bin/catm \
AMD64/bin/chmod \
AMD64/bin/cp \
AMD64/bin/get_machine \
AMD64/bin/hex2 \
AMD64/bin/kaem \
AMD64/bin/M1 \
AMD64/bin/M2-Mesoplanet \
AMD64/bin/M2-Planet \
AMD64/bin/match \
AMD64/bin/mkdir \
AMD64/bin/replace \
AMD64/bin/rm \
AMD64/bin/sha256sum \
AMD64/bin/ungz \
AMD64/bin/unbz2 \
AMD64/bin/unxz \
AMD64/bin/untar >| amd64.answers

Generate-aarch64-answers:
	sha256sum AArch64/bin/blood-elf \
AArch64/bin/catm \
AArch64/bin/chmod \
AArch64/bin/cp \
AArch64/bin/get_machine \
AArch64/bin/hex2 \
AArch64/bin/kaem \
AArch64/bin/M1 \
AArch64/bin/M2-Mesoplanet \
AArch64/bin/M2-Planet \
AArch64/bin/match \
AArch64/bin/mkdir \
AArch64/bin/replace \
AArch64/bin/rm \
AArch64/bin/sha256sum \
AArch64/bin/ungz \
AArch64/bin/unbz2 \
AArch64/bin/unxz \
AArch64/bin/untar >| aarch64.answers

Generate-riscv32-answers:
	sha256sum riscv32/bin/blood-elf \
riscv32/bin/catm \
riscv32/bin/chmod \
riscv32/bin/cp \
riscv32/bin/get_machine \
riscv32/bin/hex2 \
riscv32/bin/kaem \
riscv32/bin/M1 \
riscv32/bin/M2-Mesoplanet \
riscv32/bin/M2-Planet \
riscv32/bin/match \
riscv32/bin/mkdir \
riscv32/bin/replace \
riscv32/bin/rm \
riscv32/bin/sha256sum \
riscv32/bin/ungz \
riscv32/bin/unbz2 \
riscv32/bin/unxz \
riscv32/bin/untar >| riscv32.answers

Generate-riscv64-answers:
	sha256sum riscv64/bin/blood-elf \
riscv64/bin/catm \
riscv64/bin/chmod \
riscv64/bin/cp \
riscv64/bin/get_machine \
riscv64/bin/hex2 \
riscv64/bin/kaem \
riscv64/bin/M1 \
riscv64/bin/M2-Mesoplanet \
riscv64/bin/M2-Planet \
riscv64/bin/match \
riscv64/bin/mkdir \
riscv64/bin/replace \
riscv64/bin/rm \
riscv64/bin/sha256sum \
riscv64/bin/ungz \
riscv64/bin/unbz2 \
riscv64/bin/unxz \
riscv64/bin/untar >| riscv64.answers

.PHONY: clean
clean:
	./cleanup.sh

test-x86:
	./bootstrap-seeds/POSIX/x86/kaem-optional-seed
	sha256sum -c x86.answers

test-amd64:
	./bootstrap-seeds/POSIX/AMD64/kaem-optional-seed
	sha256sum -c amd64.answers

test-aarch64:
	./bootstrap-seeds/POSIX/AArch64/kaem-optional-seed
	sha256sum -c aarch64.answers

test-riscv32:
	./bootstrap-seeds/POSIX/riscv32/kaem-optional-seed
	sha256sum -c riscv32.answers

test-riscv64:
	./bootstrap-seeds/POSIX/riscv64/kaem-optional-seed
	sha256sum -c riscv64.answers

test-all: test-x86 test-amd64 test-aarch64 test-riscv32 test-riscv64

### dist
.PHONY: dist

COMMIT=$(shell git describe --dirty)
TARBALL_VERSION=$(COMMIT:Release_%=%)
TARBALL_DIR:=$(PACKAGE)-$(TARBALL_VERSION)
TARBALL=$(TARBALL_DIR).tar.gz
# Be friendly to Debian; avoid using EPOCH
MTIME=$(shell git show HEAD --format=%ct --no-patch)
# Reproducible tarball
TAR_FLAGS=--sort=name --mtime=@$(MTIME) --owner=0 --group=0 --numeric-owner --mode=go=rX,u+rw,a-s

$(TARBALL):
	(git ls-files --recurse-submodules		\
	    --exclude=$(TARBALL_DIR);			\
	    echo $^ | tr ' ' '\n')			\
	    | tar $(TAR_FLAGS)				\
	    --transform=s,^,$(TARBALL_DIR)/,S -T- -cf-	\
	    | gzip -c --no-name > $@

dist: $(TARBALL)
