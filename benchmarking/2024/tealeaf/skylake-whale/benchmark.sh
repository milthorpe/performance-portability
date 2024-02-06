#!/usr/bin/env bash

set -eu

function usage() {
  echo
  echo "Usage: ./benchmark.sh build|run [COMPILER] [MODEL]"
  echo
  echo "Valid compilers:"
  echo "  chapel-1.33"
  echo "  clang-17.0.6"
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

handle_cmd "${1}" "${2}" "${3}" "TeaLeaf" "skylake"

export USE_MAKE=false

case "$COMPILER" in
chapel-1.33)
  source /opt/chapel-1.33/util/setchplenv.bash
  USE_MAKE=true
  ;;
clang-17.0.6)
  append_opts "-DCMAKE_CXX_COMPILER=/usr/lib/llvm-17/bin/clang++"
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
  BENCHMARK_EXE="chapel-tealeaf"
  ;;
kokkos)
  prime_kokkos
  append_opts "-DMODEL=kokkos"
  append_opts "-DKOKKOS_IN_TREE=$KOKKOS_DIR -DKokkos_ENABLE_OPENMP=ON"
  append_opts "-DKokkos_ARCH_SKX=ON"
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
