#!/bin/bash

set -eu

SCRIPT_DIR=$(realpath "$(dirname "$(realpath "$0")")")
source "${SCRIPT_DIR}/../../common.sh"
source "${SCRIPT_DIR}/../fetch_src.sh"

spack load cmake@3.23.1

handle_cmd "${1}" "${2}" "${3}" "miniBUDE" "graviton3"

export USE_MAKE=false
export USE_SLURM=true

append_opts "-DCMAKE_VERBOSE_MAKEFILE=ON -DUSE_CPU_FEATURES=OFF"

case "$COMPILER" in
gcc-12.1)
  spack load gcc@12.1.0
  append_opts "-DCMAKE_C_COMPILER=gcc"
  append_opts "-DCMAKE_CXX_COMPILER=g++"
  # Nuke the entire flag because the default `-march=native` is broken and -mcpu=neoverse-v1 is broken too
  append_opts "-DRELEASE_FLAGS='' -DCXX_EXTRA_FLAGS=-march=armv8.4-a+rcpc+sve+profile;-Ofast"
  append_opts "-DUSE_TBB=ON"
  ;;
arm-22.0.1)
  spack load gcc@12.1.0
  spack load arm@22.0.1
  append_opts "-DCMAKE_C_COMPILER=armclang"
  append_opts "-DCMAKE_CXX_COMPILER=armclang++"
  append_opts "-DRELEASE_FLAGS='' -DCXX_EXTRA_FLAGS=-mcpu=neoverse-v1;-Ofast"
  append_opts "-DUSE_TBB=ON -DTBB_ENABLE_IPO=OFF" # IPO is broken in armclang

  export CXXFLAGS="--gcc-toolchain=$(dirname "$(which gcc)")/.."
  export LDFLAGS="--gcc-toolchain=$(dirname "$(which gcc)")/.."
  ;;
nvhpc-22.7)
  load_nvhpc
  append_opts "-DCMAKE_C_COMPILER=$NVHPC_PATH/compilers/bin/nvc"
  append_opts "-DCMAKE_CXX_COMPILER=$NVHPC_PATH/compilers/bin/nvc++"
  case "$MODEL" in
  omp)
    append_opts "-DCXX_EXTRA_FLAGS=-target=multicore;-mp;-tp=neoverse-v1;-fast;-Mx,15,0x8"
    ;;
  std-*)
    append_opts "-DCXX_EXTRA_FLAGS=-target=multicore;-stdpar;-tp=neoverse-v1;-fast;-Mx,15,0x8"
    ;;
  esac
  ;;
*) unknown_compiler ;;
esac

fetch_src

case "$MODEL" in
kokkos)
  prime_kokkos
  append_opts "-DMODEL=kokkos"
  append_opts "-DKOKKOS_IN_TREE=$KOKKOS_DIR -DKokkos_ENABLE_OPENMP=ON -DKokkos_CXX_STANDARD=17"
  append_opts "-DKokkos_ARCH_NATIVE=ON"
  BENCHMARK_EXE="kokkos-bude"
  ;;
omp)
  append_opts "-DMODEL=omp"
  BENCHMARK_EXE="omp-bude"
  ;;
tbb)
  append_opts "-DMODEL=tbb"
  BENCHMARK_EXE="tbb-bude"
  ;;
std-indices)
  append_opts "-DMODEL=std-indices"
  BENCHMARK_EXE="std-indices-bude"
  ;;
std-ranges)
  append_opts "-DMODEL=std-ranges"
  BENCHMARK_EXE="std-ranges-bude"
  ;;
std-indices-dplomp)
  append_opts "-DMODEL=std-indices -DUSE_ONEDPL=OPENMP"
  BENCHMARK_EXE="std-indices-bude"
  ;;
std-ranges-dplomp)
  append_opts "-DMODEL=std-ranges -DUSE_ONEDPL=OPENMP"
  BENCHMARK_EXE="std-ranges-bude"
  ;;
*) unknown_model ;;
esac

handle_exec