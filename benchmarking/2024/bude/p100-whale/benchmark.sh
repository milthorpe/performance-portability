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
  echo "  cuda-12"
  echo "  clang-17.0.6"
  echo
  echo "Valid models:"
  echo "  chapel"
  echo "  kokkos"
  echo "  cuda"
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

handle_cmd "${1}" "${2}" "${3}" "miniBUDE" "p100"

export USE_MAKE=false
export CUDA_PATH=/usr/local/cuda-12.4

case "$COMPILER" in
chapel-2.1)
  export PATH=${CUDA_PATH}/bin:$PATH
  export CHPL_CUDA_PATH=$CUDA_PATH
  source /opt/chapel-2.1/util/setchplenv.bash
  USE_MAKE=true
  ;;
chapel-2.0)
  export PATH=${CUDA_PATH}/bin:$PATH
  export CHPL_CUDA_PATH=$CUDA_PATH
  source /opt/chapel-2.0/util/setchplenv.bash
  USE_MAKE=true
  ;;
chapel-1.33)
  export PATH=${CUDA_PATH}/bin:$PATH
  export CHPL_CUDA_PATH=$CUDA_PATH
  source /opt/chapel-1.33/util/setchplenv.bash
  USE_MAKE=true
  ;;
chapel-1.32)
  export PATH=${CUDA_PATH}/bin:$PATH
  export CHPL_CUDA_PATH=$CUDA_PATH
  source /opt/chapel-1.32/util/setchplenv.bash
  USE_MAKE=true
  ;;
cuda-12)
  append_opts "-DCMAKE_CXX_COMPILER=$CUDA_PATH/bin/nvc++"
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
  export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}:$CUDA_PATH/lib64
  append_opts "CHPL_LOCALE_MODEL=gpu"
  append_opts "CHPL_GPU=nvidia"
  append_opts "CHPL_GPU_ARCH=sm_60"
  append_opts "PPWI=4"
  BENCHMARK_EXE="chapel-bude"
  ;;
kokkos)
  prime_kokkos
  #export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}:/usr/lib/llvm-17/lib
  export CUDA_ROOT=$CUDA_PATH
  append_opts "-DMODEL=kokkos"
  append_opts "-DKOKKOS_IN_TREE=$KOKKOS_DIR -DKokkos_ENABLE_CUDA=ON -DKokkos_ENABLE_CUDA_LAMBDA=ON"
  append_opts "-DKokkos_ARCH_PASCAL60=ON"
  append_opts "-DCMAKE_C_COMPILER=gcc"
  append_opts "-DCMAKE_CXX_COMPILER=$KOKKOS_DIR/bin/nvcc_wrapper"
  append_opts "-DCMAKE_CXX_FLAGS=-arch=sm_60"
  append_opts "-DKOKKOS_INTERNAL_CUDA_ARCH_FLAG=sm_60"
  append_opts "-DCXX_EXTRA_FLAGS=-O3;--use_fast_math"
  BENCHMARK_EXE="kokkos-bude"
  ;;
cuda)
  append_opts "-DMODEL=cuda"
  append_opts "-DCMAKE_CUDA_COMPILER=$CUDA_PATH/bin/nvcc"
  append_opts "-DCMAKE_CXX_COMPILER=g++"
  append_opts "-DCUDA_ARCH=sm_60"
  append_opts "-DCMAKE_CUDA_ARCHITECTURES=60"
  append_opts "-DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler"
  BENCHMARK_EXE="cuda-bude"
  ;;
omp)
  export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}:/usr/lib/llvm-17/lib
  append_opts "-DMODEL=omp"
  append_opts "-DOFFLOAD=NVIDIA:sm_60"
  BENCHMARK_EXE="omp-bude"
  ;;
std-data)
  append_opts "-DMODEL=std-data"
  append_opts "-DNVHPC_OFFLOAD=cc60"
  BENCHMARK_EXE="std-data-bude"
  ;;
std-indices)
  append_opts "-DMODEL=std-indices"
  append_opts "-DNVHPC_OFFLOAD=cc60"
  BENCHMARK_EXE="std-indices-bude"
  ;;
std-ranges)
  append_opts "-DMODEL=std-ranges"
  append_opts "-DNVHPC_OFFLOAD=cc60"
  BENCHMARK_EXE="std-ranges-bude"
  ;;
*) unknown_model ;;
esac

handle_exec
