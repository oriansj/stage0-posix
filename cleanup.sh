#!/usr/bin/env bash
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

set -eux

# clean up the core repo
git clean -xdf

# clean up after x86
pushd x86
git clean -xdf
popd

# clean up after AMD64
pushd AMD64
git clean -xdf
popd

# clean up after AArch64
pushd AArch64
git clean -xdf
popd

# clean up after riscv32
pushd riscv32
git clean -xdf
popd

# clean up after riscv64
pushd riscv64
git clean -xdf
popd
