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
  echo "  clang-17.0.1"
  echo "  gcc-12.2.0"
  echo "  intel-2023"
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

module load cmake/3.24.2

handle_cmd "${1}" "${2}" "${3}" "babelstream" "sapphirerapids"

export USE_MAKE=false

case "$COMPILER" in
chapel-2.1)
  module load gcc/12.2.0 llvm/17.0.1
  source /scratch/vp91/chapel-2.1/util/setchplenv.bash
  export CHPL_LLVM=system
  export CHPL_TARGET_CPU=sapphirerapids
  export CHPL_COMM=none
  export CHPL_LAUNCHER=none
  USE_MAKE=true
  ;;
chapel-2.0)
  module load gcc/12.2.0 llvm/17.0.1
  source /scratch/px94/chapel-2.0/util/setchplenv.bash
  export CHPL_LLVM=system
  export CHPL_TARGET_CPU=sapphirerapids
  export CHPL_COMM=none
  export CHPL_LAUNCHER=none
  USE_MAKE=true
  ;;
chapel-1.33)
  module load gcc/12.2.0
  source /scratch/px94/chapel-1.33/util/setchplenv.bash
  export CHPL_LLVM=bundled
  export CHPL_TARGET_CPU=sapphirerapids
  export CHPL_COMM=none
  export CHPL_LAUNCHER=none
  USE_MAKE=true
  ;;
gcc-12.2.0)
  module load gcc/12.2.0
  append_opts "-DCMAKE_CXX_COMPILER=`which g++`"
  append_opts "-DCXX_EXTRA_FLAGS=-march=sapphirerapids"
  ;;
clang-17.0.1)
  module load llvm/17.0.1
  append_opts "-DCMAKE_CXX_COMPILER=`which clang++`"
  append_opts "-DCXX_EXTRA_FLAGS=-march=sapphirerapids"
  ;;
intel-2023)
  module load intel-compiler-llvm/2023.2.0
  append_opts "-DCMAKE_CXX_COMPILER=`which icpx`"
  append_opts "-DCXX_EXTRA_FLAGS=-march=sapphirerapids"
  ;;
*) unknown_compiler ;;
esac

if [ "$USE_MAKE" = false ]; then
  append_opts "-DCMAKE_VERBOSE_MAKEFILE=ON"
fi

fetch_src

case "$MODEL" in
chapel)
  BENCHMARK_EXE="chapel-stream"
  append_opts "CHPL_LOCALE_MODEL=flat"
  ;;
kokkos)
  prime_kokkos
  append_opts "-DMODEL=kokkos"
  append_opts "-DKOKKOS_IN_TREE=$KOKKOS_DIR -DKokkos_ENABLE_OPENMP=ON"
  append_opts "-DKokkos_ARCH_SPR=ON"
  BENCHMARK_EXE="kokkos-stream"
  ;;
omp)
  append_opts "-DMODEL=omp"
  BENCHMARK_EXE="omp-stream"
  ;;
std-data)
  append_opts "-DMODEL=std-data"
  BENCHMARK_EXE="std-data-stream"
  ;;
std-indices)
  append_opts "-DMODEL=std-indices"
  BENCHMARK_EXE="std-indices-stream"
  ;;
std-ranges)
  append_opts "-DMODEL=std-ranges"
  BENCHMARK_EXE="std-ranges-stream"
  ;;
*) unknown_model ;;
esac

handle_exec
