# Copyright (C) 2021-2023 by the FEM on Colab authors
#
# This file is part of FEM on Colab.
#
# SPDX-License-Identifier: MIT

set -e
set -x

REPODIR=$PWD

# Expect one argument to set the scalar type
: ${1?"Usage: $0 scalar_type"}
SCALAR_TYPE="$1"
if [[ "$SCALAR_TYPE" != "complex" ]]; then
    SCALAR_TYPE="real"
fi

# Install boost, pybind11, slepc4py and vtk (and their dependencies)
FIREDRAKE_ARCHIVE_PATH="skip" source firedrake/install.sh

# islpy
PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install --user --no-binary=islpy islpy

# COFFEE
git clone https://github.com/coneoproject/COFFEE.git /tmp/coffee-src
cd /tmp/coffee-src
PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install . --user

# loopy
git clone https://github.com/firedrakeproject/loopy.git /tmp/loopy-src
cd /tmp/loopy-src
git submodule update --init --recursive
PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install . --user

# netCDF4-python
git clone https://github.com/Unidata/netcdf4-python.git /tmp/netcdf4-python-src
cd /tmp/netcdf4-python-src
PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install . --no-build-isolation --user

# FIAT
git clone https://github.com/firedrakeproject/fiat.git /tmp/fiat-src
cd /tmp/fiat-src
patch -p 1 < $REPODIR/firedrake/patches/05-pkg-resources-to-importlib-in-fiat
PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install . --user

# FInAT
git clone https://github.com/FInAT/FInAT.git /tmp/finat-src
cd /tmp/finat-src
PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install . --user

# UFL
git clone https://github.com/firedrakeproject/ufl.git /tmp/ufl-src
cd /tmp/ufl-src
PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install . --user

# TSFC
git clone https://github.com/firedrakeproject/tsfc.git /tmp/tsfc-src
cd /tmp/tsfc-src
PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install . --user

# PyOP2
git clone https://github.com/OP2/PyOP2.git /tmp/pyop2-src
cd /tmp/pyop2-src
if [[ "$LDFLAGS" == *"-static-libstdc++"* ]]; then
    patch -p 1 < $REPODIR/firedrake/patches/01-pyop2-static-libstdc++
fi
export PETSC_DIR=$INSTALL_PREFIX
PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install . --user

# pyadjoint
git clone https://github.com/dolfin-adjoint/pyadjoint /tmp/pyadjoint-src
cd /tmp/pyadjoint-src
PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install . --user

# libsupermesh
git clone https://github.com/firedrakeproject/libsupermesh.git /tmp/libsupermesh-src
cd /tmp/libsupermesh-src
patch -p 1 < $REPODIR/firedrake/patches/08-use-cxxflags-in-supermesh
mkdir -p /tmp/libsupermesh-src/build
cd /tmp/libsupermesh-src/build
cmake \
    -DCMAKE_C_COMPILER=$(which mpicc) \
    -DCMAKE_CXX_COMPILER=$(which mpicxx) \
    -DCMAKE_CXX_FLAGS="$CPPFLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
    -DCMAKE_SKIP_RPATH:BOOL=ON \
    -DCMAKE_INSTALL_PREFIX:PATH=$INSTALL_PREFIX \
    -DBUILD_SHARED_LIBS:BOOL=ON \
    ..
make -j $(nproc) install

# TinyASM
git clone https://github.com/florianwechsung/TinyASM.git /tmp/tinyasm-src
cd /tmp/tinyasm-src
patch -p 1 < $REPODIR/firedrake/patches/02-use-system-pybind11-in-tinyasm
patch -p 1 < $REPODIR/firedrake/patches/07-use-cxxflags-and-ldflags-in-tinyasm
export PYBIND11_DIR=$INSTALL_PREFIX
PYTHONUSERBASE=$INSTALL_PREFIX CXX="mpicxx" CXXFLAGS=$CPPFLAGS python3 -m pip install . --user

# libspatialindex
git clone https://github.com/firedrakeproject/libspatialindex.git /tmp/libspatialindex-src
mkdir -p /tmp/libspatialindex-src/build
cd /tmp/libspatialindex-src/build
cmake \
    -DCMAKE_C_COMPILER=$(which mpicc) \
    -DCMAKE_CXX_COMPILER=$(which mpicxx) \
    -DCMAKE_CXX_FLAGS="$CPPFLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
    -DCMAKE_SKIP_RPATH:BOOL=ON \
    -DCMAKE_INSTALL_PREFIX:PATH=$INSTALL_PREFIX \
    ..
make -j $(nproc) install

# firedrake
git clone https://github.com/firedrakeproject/firedrake.git /tmp/firedrake-src
cd /tmp/firedrake-src
if [[ "$SCALAR_TYPE" == "complex" ]]; then
    patch -p 1 < $REPODIR/firedrake/patches/03-hardcode-complex-mode-in-firedrake
else
    patch -p 1 < $REPODIR/firedrake/patches/03-hardcode-real-mode-in-firedrake
fi
sed -i "s|INSTALL_PREFIX_IN|${INSTALL_PREFIX}|g" $REPODIR/firedrake/patches/04-hardcode-petsc-dir-omp-num-threads-in-firedrake
patch -p 1 < $REPODIR/firedrake/patches/04-hardcode-petsc-dir-omp-num-threads-in-firedrake
PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install . --user

# Write out configuration file
mkdir -p tmp_for_global_import && cd tmp_for_global_import
CONFIGURATION_FILE=$(python3 -c 'import firedrake_configuration, os; print(os.path.join(os.path.dirname(firedrake_configuration.__file__), "configuration.json"))')
cd .. && rm -rf tmp_for_global_import
if [[ "$SCALAR_TYPE" == "complex" ]]; then
    IS_COMPLEX="true"
else
    IS_COMPLEX="false"
fi
cat <<EOT > $CONFIGURATION_FILE
{
  "options": {
    "cache_dir": "/root/.cache/firedrake",
    "complex": $IS_COMPLEX,
    "honour_petsc_dir": true,
    "petsc_int_type": "int32"
  }
}
EOT

# firedrake run dependencies
PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install --user cachetools progress

# fireshape dependencies (real mode only)
# We package them for simplicity with firedrake so that fireshape may be pip installed.
if [[ "$SCALAR_TYPE" != "complex" ]]; then
    # pyrol + roltrilinos
    git clone --branch rol-2.0-checkpointing https://github.com/angus-g/pyrol /tmp/rol-src
    cd /tmp/rol-src
    patch -p 1 < $REPODIR/firedrake/patches/06-use-system-pybind11-in-pyrol
    export PYBIND11_DIR=$INSTALL_PREFIX
    # pip fails this with cmake import error...
    #PYTHONUSERBASE=$INSTALL_PREFIX CXX="mpicxx" CXXFLAGS=$CPPFLAGS python3 -m pip install . --user
    PYTHONUSERBASE=$INSTALL_PREFIX python3 setup.py install

    # wurlitzer (only used in notebooks to redirect the C++ output to the notebook cell ouput)
    PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install --user wurlitzer

    PYTHONUSERBASE=$INSTALL_PREFIX python3 -m pip install --user git+https://github.com/g-adopt/g-adopt@gadopt-restructure
fi
