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
	sha256sum x86/bin/* >| x86.answers

Generate-amd64-answers:
	sha256sum AMD64/bin/* >| amd64.answers

Generate-aarch64-answers:
	sha256sum AArch64/bin/* >| aarch64.answers

Generate-riscv64-answers:
	sha256sum riscv64/bin/* >| riscv64.answers

.PHONY: clean
clean:
	git clean -xdf

test-x86:
	./bootstrap-seeds/POSIX/x86/kaem-optional-seed
	sha256sum -c x86.answers

test-amd64:
	./bootstrap-seeds/POSIX/AMD64/kaem-optional-seed
	sha256sum -c amd64.answers

test-aarch64:
	cd AArch64 && ../bootstrap-seeds/POSIX/AArch64/kaem-optional-seed
	sha256sum -c aarch64.answers

test-riscv64:
	./bootstrap-seeds/POSIX/riscv64/kaem-optional-seed
	sha256sum -c riscv64.answers

test-all: test-x86 test-amd64 test-aarch64 test-riscv64

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
	(git ls-files					\
	    --exclude=$(TARBALL_DIR);			\
	    echo $^ | tr ' ' '\n')			\
	    | tar $(TAR_FLAGS)				\
	    --transform=s,^,$(TARBALL_DIR)/,S -T- -cf-	\
	    | gzip -c --no-name > $@

dist: $(TARBALL)
