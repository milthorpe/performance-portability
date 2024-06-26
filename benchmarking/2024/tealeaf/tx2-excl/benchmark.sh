#!/usr/bin/env bash

set -eu

function usage() {
  echo
  echo "Usage: ./benchmark.sh build|run [COMPILER] [MODEL]"
  echo
  echo "Valid compilers:"
  echo "  chapel-2.0"
  echo "  chapel-1.33"
  echo "  clang-17.0.2"
  echo
  echo "Valid models:"
  echo "  chapel"
  echo "  kokkos"
  echo "  omp"
  echo "  std-data"
  echo "  std-indices"
  echo "  std-ranges"
  echo
}

# Process arguments
if [ $# -lt 3 ]; then
  usage
  exit 1
fi

SCRIPT_DIR=$(realpath "$(dirname "$(realpath "$0")")")
source "${SCRIPT_DIR}/../../common.sh"
source "${SCRIPT_DIR}/../fetch_src.sh"

handle_cmd "${1}" "${2}" "${3}" "TeaLeaf" "tx2"

export USE_MAKE=false

case "$COMPILER" in
chapel-2.0)
  source /noback/46x/chapel-2.0_centos8/util/setchplenv.bash
  USE_MAKE=true
  ;;
chapel-1.33)
  source /noback/46x/chapel-1.33_centos8/util/setchplenv.bash
  USE_MAKE=true
  ;;
clang-17.0.2)
  append_opts "-DCMAKE_CXX_COMPILER=/usr/lib64/ccache/clang++"
  ;;
*) unknown_compiler ;;
esac

if [ "$USE_MAKE" = false ]; then
  append_opts "-DCMAKE_VERBOSE_MAKEFILE=ON"
fi

fetch_src

case "$MODEL" in
chapel)
  append_opts "CHPL_LOCALE_MODEL=flat"
  append_opts "CHPL_TARGET_ARCH=aarch64"
  append_opts "CHPL_TARGET_CPU=thunderx2t99"
  BENCHMARK_EXE="chapel-tealeaf"
  ;;
kokkos)
  prime_kokkos
  append_opts "-DMODEL=kokkos"
  append_opts "-DKOKKOS_IN_TREE=$KOKKOS_DIR -DKokkos_ENABLE_OPENMP=ON"
  append_opts "-DKokkos_ARCH_ARMV8_THUNDERX2=ON"
  BENCHMARK_EXE="kokkos-tealeaf"
  ;;
omp)
  append_opts "-DMODEL=omp"
  BENCHMARK_EXE="omp-tealeaf"
  ;;
std-data)
  append_opts "-DMODEL=std-data"
  BENCHMARK_EXE="std-data-tealeaf"
  ;;
std-indices)
  append_opts "-DMODEL=std-indices"
  BENCHMARK_EXE="std-indices-tealeaf"
  ;;
std-ranges)
  append_opts "-DMODEL=std-ranges"
  BENCHMARK_EXE="std-ranges-tealeaf"
  ;;
*) unknown_model ;;
esac

handle_exec
