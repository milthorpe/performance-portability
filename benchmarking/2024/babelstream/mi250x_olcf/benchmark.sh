#!/usr/bin/env bash

set -eu

function usage() {
  echo
  echo "Usage: ./benchmark.sh build|run [COMPILER] [MODEL]"
  echo
  echo "Valid compilers:"
  echo "  chapel-1.33"
  echo "  chapel-2.0"
  echo "  chapel-2.1"
  echo "  rocm-5.4.3"
  echo "  rocm-6.0.0"
  echo
  echo "Valid models:"
  echo "  chapel"
  echo "  kokkos"
  echo "  hip"
  echo "  omp"
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

export USE_SLURM=true

module load cmake/3.23.2

handle_cmd "${1}" "${2}" "${3}" "babelstream" "mi250x"

export USE_MAKE=false

case "$COMPILER" in
chapel-1.33)
  module load cray-python amd/5.4.3 PrgEnv-amd/8.5.0
  source /lustre/orion/csc567/world-shared/milthorpe/chapel-1.33/util/setchplenv.bash
  export CHPL_LLVM=bundled
  export CHPL_COMM=none
  export CHPL_LAUNCHER=none
  USE_MAKE=true
  ;;
chapel-2.0)
  module load cray-python amd/5.4.3 PrgEnv-amd/8.5.0
  source /lustre/orion/csc567/world-shared/milthorpe/chapel-2.0/util/setchplenv.bash
  export CHPL_LLVM=system
  export CHPL_COMM=none
  export CHPL_LAUNCHER=none
  USE_MAKE=true
  ;;
chapel-2.1)
  module load cray-python amd/5.4.3 PrgEnv-amd/8.5.0
  source /lustre/orion/csc567/world-shared/milthorpe/chapel/util/setchplenv.bash
  export CHPL_LLVM=system
  export CHPL_COMM=none
  export CHPL_LAUNCHER=none
  USE_MAKE=true
  ;;
rocm-5.4.3)
  module load amd/5.4.3
  export PATH="${ROCM_PATH}/bin:${PATH:-}"
  ;;
rocm-6.0.0)
  module load amd/6.0.0
  export PATH="${ROCM_PATH}/bin:${PATH:-}"
  ;;
*) unknown_compiler ;;
esac

if [ "$USE_MAKE" = false ]; then
  append_opts "-DCMAKE_VERBOSE_MAKEFILE=ON"
fi

fetch_src

case "$MODEL" in
chapel)
  append_opts "CHPL_LOCALE_MODEL=gpu"
  append_opts "CHPL_GPU=amd"
  append_opts "CHPL_GPU_ARCH=gfx90a"
  BENCHMARK_EXE="chapel-stream"
  ;;
kokkos)
  prime_kokkos
  append_opts "-DMODEL=kokkos"
  append_opts "-DKOKKOS_IN_TREE=$KOKKOS_DIR -DKokkos_ENABLE_HIP=ON"
  append_opts "-DKokkos_ARCH_AMD_GFX90A=ON"
  append_opts "-DCMAKE_C_COMPILER=gcc"
  append_opts "-DCMAKE_CXX_COMPILER=hipcc"
  BENCHMARK_EXE="kokkos-stream"
  ;;
hip)
  append_opts "-DMODEL=hip"
  append_opts "-DCMAKE_C_COMPILER=gcc"
  append_opts "-DCMAKE_CXX_COMPILER=hipcc" # auto detected
  append_opts "-DCXX_EXTRA_FLAGS=--offload-arch=gfx90a"
  BENCHMARK_EXE="hip-stream"
  ;;
omp)
  module load craype-accel-amd-gfx90a
  append_opts "-DCMAKE_CXX_COMPILER=$(which amdclang++)"
  append_opts "-DMODEL=omp"
  append_opts "-DOFFLOAD=AMD:gfx90a"
  append_opts "-DCXX_EXTRA_FLAGS=-fopenmp-target-fast"
  BENCHMARK_EXE="omp-stream"
  ;;
*) unknown_model ;;
esac

handle_exec
