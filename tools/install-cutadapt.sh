#!/bin/bash

# autoadapt - Automatic quality control for FASTQ sequencing files
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

echo "Installing cutadapt..."

# TODO install python and cython
# sudo apt-get -y --force-yes install python-setuptools
# sudo easy_install cython

CUTADAPT_BUILD_DIR="${SCRIPT_DIR}/build/cutadapt"
CUTADAPT_INSTALL_DIR="${SCRIPT_DIR}/install/cutadapt"

rm -rf "${CUTADAPT_BUILD_DIR}"
mkdir -p "${CUTADAPT_BUILD_DIR}"

rm -rf "${CUTADAPT_INSTALL_DIR}"
mkdir -p "${CUTADAPT_INSTALL_DIR}"

tar -xvf archives/cutadapt-1.3.tar.gz -C "${SCRIPT_DIR}/build"

pushd "${CUTADAPT_BUILD_DIR}" > /dev/null

python setup.py build
python setup.py install --prefix "${CUTADAPT_INSTALL_DIR}"

CUTADAPT_LAUNCHER="${SCRIPT_DIR}/cutadapt"
rm -f "${CUTADAPT_LAUNCHER}"

echo '#!/usr/bin/env bash' >> "${CUTADAPT_LAUNCHER}"
echo 'PYTHONPATH='"${CUTADAPT_INSTALL_DIR}/lib/python2.7/site-packages"':$PYTHON_PATH '"${CUTADAPT_INSTALL_DIR}/bin/cutadapt"' $@' >> "${CUTADAPT_LAUNCHER}"

chmod a+rwx "${CUTADAPT_LAUNCHER}"

popd > /dev/null

echo "Finished installing cutadapt."

popd > /dev/null
