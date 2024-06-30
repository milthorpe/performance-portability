#!/usr/bin/env bash

set -eu

function usage() {
  echo
  echo "Usage: ./benchmark.sh build|run [COMPILER] [MODEL]"
  echo
  echo "Valid compilers:"
  echo "  chapel-2.0"
  echo "  chapel-1.33"
  echo "  rocm-5.4.3"
  echo "  aomp-18.0.0"
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

module load cmake/3.23.2

handle_cmd "${1}" "${2}" "${3}" "miniBUDE" "mi250"

export USE_MAKE=false
export USE_SLURM=true

case "$COMPILER" in
chapel-2.1)
  module load cray-python amd/5.4.3 PrgEnv-amd/8.5.0
  source /lustre/orion/csc567/world-shared/milthorpe/chapel/util/setchplenv.bash
  export CHPL_LLVM=system
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
chapel-1.33)
  module load cray-python amd/5.4.3 PrgEnv-amd/8.5.0
  source /lustre/orion/csc567/world-shared/milthorpe/chapel-1.33/util/setchplenv.bash
  export CHPL_LLVM=system
  export CHPL_COMM=none
  export CHPL_LAUNCHER=none
  USE_MAKE=true
  ;;
rocm-5.4.3)
  module load rocm/5.4.3
  export PATH="${ROCM_PATH}/bin:${PATH:-}"
  ;;
rocm-6.0.0)
  module load rocm/6.0.0
  export PATH="${ROCM_PATH}/bin:${PATH:-}"
  ;;
aomp-18.0.0)
  module load rocm/5.4.3
  export AOMP=$HOME/usr/lib/aomp_18.0-0
  export PATH="$AOMP/bin:${PATH:-}"
  export LD_LIBRARY_PATH="$AOMP/lib64:${LD_LIBRARY_PATH:-}"
  export LIBRARY_PATH="$AOMP/lib64:${LIBRARY_PATH:-}"
  export C_INCLUDE_PATH="$AOMP/include:${C_INCLUDE_PATH:-}"
  export CPLUS_INCLUDE_PATH="$AOMP/include:${CPLUS_INCLUDE_PATH:-}"
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
  append_opts "PPWI=4"
  BENCHMARK_EXE="chapel-bude"
  ;;
kokkos)
  prime_kokkos
  append_opts "-DMODEL=kokkos"
  append_opts "-DKOKKOS_IN_TREE=$KOKKOS_DIR -DKokkos_ENABLE_HIP=ON"
  append_opts "-DKokkos_ARCH_AMD_GFX90A=ON"
  append_opts "-DCMAKE_C_COMPILER=gcc"
  append_opts "-DCMAKE_CXX_COMPILER=hipcc"
  append_opts "-DCXX_EXTRA_FLAGS=-Ofast"
  BENCHMARK_EXE="kokkos-bude"
  ;;
hip)
  append_opts "-DMODEL=hip"
  append_opts "-DCMAKE_C_COMPILER=gcc"
  append_opts "-DCMAKE_CXX_COMPILER=hipcc" # auto detected
  append_opts "-DCXX_EXTRA_FLAGS=--offload-arch=gfx90a;-Ofast"
  BENCHMARK_EXE="hip-bude"
  ;;
omp)
  module load craype-accel-amd-gfx90a
  append_opts "-DCMAKE_CXX_COMPILER=$(which amdclang++)"
  append_opts "-DMODEL=omp"
  append_opts "-DOFFLOAD=AMD:gfx90a"
  append_opts "-DCXX_EXTRA_FLAGS=-Ofast;-fopenmp-target-fast"
  BENCHMARK_EXE="omp-bude"
  ;;
*) unknown_model ;;
esac

handle_exec
