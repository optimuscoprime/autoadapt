#!/bin/bash

# autoadapt - Automatically detect and remove adaptors in FASTQ files
# Copyright (C) 2013  Rupert Shuttleworth
# optimuscoprime@gmail.com

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Rupert Shuttleworth 2013
# optimuscoprime@gmail.com

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

pushd "${SCRIPT_DIR}" > /dev/null

set -e
set -o pipefail

echo "Installing FastQC..."

FASTQC_INSTALL_DIR="${SCRIPT_DIR}/install/FastQC"

rm -rf "${FASTQC_INSTALL_DIR}"
mkdir -p "${FASTQC_INSTALL_DIR}"

unzip archives/fastqc_v0.10.1.zip -d "${SCRIPT_DIR}/install"

pushd "${FASTQC_INSTALL_DIR}" > /dev/null

chmod a+rwx -R *

popd > /dev/null

ln -s -f "${FASTQC_INSTALL_DIR}/fastqc" "${SCRIPT_DIR}/fastqc"

echo "Finished installing FastQC."

popd > /dev/null
