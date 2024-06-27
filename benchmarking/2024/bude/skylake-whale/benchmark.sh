#!/usr/bin/env bash

set -eu

function usage() {
  echo
  echo "Usage: ./benchmark.sh build|run [COMPILER] [MODEL]"
  echo
  echo "Valid compilers:"
  echo "  chapel-2.1"
  echo "  chapel-2.0"
  echo "  chapel-1.33"
  echo "  chapel-1.32"
  echo "  chapel-1.31"
  echo "  chapel-1.30"
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

handle_cmd "${1}" "${2}" "${3}" "miniBUDE" "skylake"

export USE_MAKE=false

case "$COMPILER" in
chapel-2.1)
  source /opt/chapel-2.1/util/setchplenv.bash
  USE_MAKE=true
  ;;
chapel-2.0)
  source /opt/chapel-2.0/util/setchplenv.bash
  USE_MAKE=true
  ;;
chapel-1.33)
  source /opt/chapel-1.33/util/setchplenv.bash
  USE_MAKE=true
  ;;
chapel-1.32)
  source /opt/chapel-1.32/util/setchplenv.bash
  USE_MAKE=true
  ;;
chapel-1.31)
  source /opt/chapel-1.31/util/setchplenv.bash
  USE_MAKE=true
  ;;
chapel-1.30)
  source /opt/chapel-1.30/util/setchplenv.bash
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
  BENCHMARK_EXE="chapel-bude"
  append_opts "CHPL_LOCALE_MODEL=flat"
  append_opts "PPWI=128"
  ;;
kokkos)
  prime_kokkos
  append_opts "-DMODEL=kokkos"
  append_opts "-DKOKKOS_IN_TREE=$KOKKOS_DIR -DKokkos_ENABLE_OPENMP=ON"
  append_opts "-DKokkos_ARCH_SKX=ON"
  BENCHMARK_EXE="kokkos-bude"
  ;;
omp)
  append_opts "-DMODEL=omp"
  BENCHMARK_EXE="omp-bude"
  ;;
std-data)
  append_opts "-DMODEL=std-data"
  BENCHMARK_EXE="std-data-bude"
  ;;
std-indices)
  append_opts "-DMODEL=std-indices"
  BENCHMARK_EXE="std-indices-bude"
  ;;
std-ranges)
  append_opts "-DMODEL=std-ranges"
  BENCHMARK_EXE="std-ranges-bude"
  ;;
*) unknown_model ;;
esac

handle_exec
