# shellcheck shell=bash

set -eu
set -o pipefail

function loadOneAPI() {
  if [ -z "${1:-}" ]; then
    echo "${FUNCNAME[0]}: Usage: ${FUNCNAME[0]} /path/to/oneapi/source.sh"
    echo "No OneAPI path provided. Stop."
    exit 5
  fi

  local oneapi_env="${1}"

  set +u # setvars can't handle unbound vars
  CURRENT_SCRIPT_DIR="$SCRIPT_DIR" # save current script dir as the setvars overwrites it

  # their script also terminates the shell for some reason so we short-circuit it first
  source "$oneapi_env"  --force || true

  set -u
  SCRIPT_DIR="$CURRENT_SCRIPT_DIR" #recover script dir
}

function findhipSYCL(){
  local HIPSYCL_PATH="$(realpath "$(dirname "$(which syclcc)")"/..)"
  if [ ! -d "$HIPSYCL_PATH" ]; then
    echo "No hipSYCL path found based on the location of syclcc, is hipsycl loaded?"
    exit 5
  fi
  echo "$HIPSYCL_PATH"
}

function findComputeCpp(){
  local COMPUTECPP_PATH="$(realpath "$(dirname "$(which compute++)")"/..)"
  if [ ! -d "$COMPUTECPP_PATH" ]; then
    echo "No ComputeCpp path found based on the location of compute++, is computecpp loaded?"
    exit 5
  fi
  echo "$COMPUTECPP_PATH"
}

function findOneAPIlibOpenCL(){
  local ICD_PATH="$(realpath "$(dirname "$(which icpx)")"/..)/lib/libOpenCL.so.1"
  if [ ! -f "$ICD_PATH" ]; then
    echo "No OpenCL lib (ICD) found based on the location of icpx, is oneAPI loaded?"
    exit 5
  fi
  echo "$ICD_PATH"
}

function findGCC(){
  local GCC_PATH="$(realpath "$(dirname "$(which gcc)")"/..)"
  if [ ! -d "$GCC_PATH" ]; then
    echo "No GCC path found based on the location of gcc, is gcc loaded?"
    exit 5
  fi
  echo "$GCC_PATH"
}

function fetchCLHeader(){
  local CL_HEADER_DIR="$PWD/OpenCL-Headers-2020.06.16"
  local TARBALL="v2020.06.16.tar.gz"
  if [ ! -d "$CL_HEADER_DIR" ]; then
    wget "https://github.com/KhronosGroup/OpenCL-Headers/archive/$TARBALL"
    tar -xf "$TARBALL"
    rm -rf "$TARBALL"
  fi
  echo "$CL_HEADER_DIR"
}

function usage() {
  echo
  echo "Usage: ./benchmark.sh build|run [MODEL] [COMPILER]"
  echo
  echo "Valid model and compiler options for CloverLeaf:"
  echo "  omp"
  echo "    arm-20.0"
  echo "    cce-10.0"
  echo "    cce-sve-10.0"
  echo "    gcc-8.1"
  echo "    gcc-9.3"
  echo "    gcc-10.2"
  echo "    gcc-11.0"
  echo
  echo "  omp-target"
  echo "    aomp-11.12"
  echo "    icpx-2021.1"
  echo "    cce-10.0"
  echo "    llvm-10.0"
  echo
  echo "  ocl"
  echo "    gcc-9.3"
  echo "    gcc-10.1"
  echo
  echo "  cuda"
  echo "    gcc-8.1"
  echo "    gcc-10.1"
  echo
  echo "  acc"
  echo "    cce-9.1-classic"
  echo "    pgi-19.10"
  echo
  echo "  kokkos"
  echo "    arm-20.0"
  echo "    cce-10.0"
  echo "    gcc-9.3"
  echo "    gcc-10.2"
  echo
  echo "  sycl"
  echo "    hipsycl-201124-gcc9.3"
  echo "    oneapi-2021.1-beta10"
  echo
  echo "Selected platform: $PLATFORM"
  echo "  Compilers available: $COMPILERS"
  echo "  Models available: $MODELS"
  echo
  echo "The default configuration is '$DEFAULT_MODEL $DEFAULT_COMPILER'."
  echo
}

# Process arguments
if [ $# -lt 1 ]; then
  usage
  exit 1
elif [ "$1" = '-h' ] || [ "$1" = '--help' ]; then
  usage
  exit
fi


action="$1"
export MODEL="${2:-$DEFAULT_MODEL}"
export COMPILER="${3:-$DEFAULT_COMPILER}"
export CONFIG="${PLATFORM}_${COMPILER}_${MODEL}"

if [[ ! "$MODELS" =~ $MODEL ]] || [[ ! "$COMPILERS" =~ $COMPILER ]]; then
  echo "Configuration '$MODEL $COMPILER' not available on $PLATFORM."
  exit 2
fi

# export SRC_DIR="$PWD/bude-portability-benchmark"
export RUN_DIR="$PWD/cloverleaf-$CONFIG"
export BENCHMARK_EXE="cloverleaf_$CONFIG"

# Set up the environment
setup_env

USE_CMAKE=false
# Setup model
case "$MODEL" in
  omp|mpi)
    if [ ! -e CloverLeaf_ref/clover.f90 ]; then
      git clone https://github.com/UK-MAC/CloverLeaf_ref
    fi
    ( cd CloverLeaf_ref || exit; git checkout 612c2da46cffe26941e5a06492215bdef2c3f971 )
    export SRC_DIR="$PWD/CloverLeaf_ref"
    export BINARY="clover_leaf"
    ;;
  omp-target)
    if [ ! -e cloverleaf_openmp_target/CMakeLists.txt ]; then
      git clone -b omp-target https://github.com/UoB-HPC/cloverleaf_openmp_target
    fi
    # icpx(icc) supports offloading too, see
    # https://software.intel.com/content/www/us/en/develop/documentation/get-started-with-cpp-fortran-compiler-openmp
    if ! [[ "$COMPILER" =~ (cce|gcc|llvm)-10 || "$COMPILER" =~ (aomp|icpx) ]]; then
      echo "Model '$MODEL' can only be used with compilers: cce-10.0 llvm-10.0."
      exit 3
    fi
    export SRC_DIR="$PWD/cloverleaf_openmp_target"
    export BINARY="clover_leaf"
    USE_CMAKE=true
    ;;
  ocl)
    if [ ! -e CloverLeaf_OpenCL/clover_leaf.f90 ]; then
      git clone https://github.com/UK-MAC/CloverLeaf_OpenCL
    fi
    CL_HEADER_DIR="$PWD/OpenCL-Headers-2020.06.16"
    if [ ! -d "$CL_HEADER_DIR" ]; then
      wget https://github.com/KhronosGroup/OpenCL-Headers/archive/v2020.06.16.tar.gz
      tar -xf v2020.06.16.tar.gz
    fi
    
    export SRC_DIR="$PWD/CloverLeaf_OpenCL"
    export BINARY="clover_leaf"

    

    # loadOneAPI /lustre/projects/bristol/modules/intel/oneapi/2021.1/setvars.sh
    # MAKE_OPTS+=" USE_OPENCL=1"
    # MAKE_OPTS+=' COPTIONS="-std=c++98 -DCL_TARGET_OPENCL_VERSION=110 -DOCL_IGNORE_PLATFORM"'
    # MAKE_OPTS+=' OPTIONS="-lstdc++ -cpp -lOpenCL"'
    # MAKE_OPTS+=" OCL_VENDOR=AMD" 
    # MAKE_OPTS+=" OCL_LIB_AMD_INC=$(fetchCLHeader)"
    # MAKE_OPTS+=" OCL_AMD_LIB=-L$(findOneAPIlibOpenCL)"
    
   
    # export C_INCLUDE_PATH="$CL_HEADER_DIR:${C_INCLUDE_PATH:-}"
   
    ;;

  cuda)
    if [ ! -e CloverLeaf_CUDA/clover_leaf.f90 ]; then
      git clone --depth 1 "https://github.com/UK-MAC/CloverLeaf_CUDA.git"
    fi
    if [[ "$PLATFORM" =~ isamabrd ]] && [ "$COMPILER" != gcc-8.1 ]; then
      echo "Model '$MODEL' can only be used with compiler 'gcc-8.1' on platform '$PLATFORM'."
      exit 3
    elif [[ "$PLATFORM" =~ zoo ]] && [ "$COMPILER" != gcc-10.1 ]; then
      echo "Model '$MODEL' can only be used with compiler 'gcc-10.1' on platform '$PLATFORM'."
      exit 3
    fi

    export SRC_DIR="$PWD/CloverLeaf_CUDA"
    export BINARY="clover_leaf"
    
    ;;
  acc)
    if [[ ! "$COMPILER" =~ (cce-9.1-classic|pgi-19.10) ]]; then
      echo "Model '$MODEL' can only be used with compilers: cce-9.1-classic pgi-19.10."
      exit 3
    fi
    export SRC_DIR="$PWD/openacc"
    export BINARY="clover_leaf"
    ;;
  kokkos)
    if [ ! -e cloverleaf_kokkos/clover_leaf.cpp ]; then
      git clone "https://github.com/UoB-HPC/cloverleaf_kokkos"
    fi
    export SRC_DIR="$PWD/cloverleaf_kokkos"
    export BINARY="clover_leaf"
    USE_CMAKE=true

    KOKKOS_VER="3.2.01"
    KOKKOS_DIR="$(realpath kokkos-$KOKKOS_VER)"
    echo "Using Kokkos src $KOKKOS_DIR"

    if [ ! -e "$KOKKOS_DIR" ]; then
       wget "https://github.com/kokkos/kokkos/archive/$KOKKOS_VER.tar.gz"
       tar -xf "$KOKKOS_VER.tar.gz"
       rm "$KOKKOS_VER.tar.gz"
    fi

    # We're using CMake with in-tree Kokkos here
    # So let's wipe out the existing make flags
    MAKE_OPTS="-DKOKKOS_IN_TREE=$KOKKOS_DIR"

    if [ -n "${KOKKOS_BACKEND:-}" ]; then
      echo "Using Kokkos backend=$KOKKOS_BACKEND"
      MAKE_OPTS+=" -DKokkos_ENABLE_$KOKKOS_BACKEND=ON"
    else
      echo "KOKKOS_BACKEND was not specified, this should be done in the setup_env() part of the script but wasn't"
      exit 1
    fi

    if [ -n "${KOKKOS_ARCH:-}" ]; then
      echo "Using Kokkos arch=$KOKKOS_ARCH"
      MAKE_OPTS+=" -DKokkos_ARCH_$KOKKOS_ARCH=ON"
    else
      echo "KOKKOS_ARCH was not specified, this should be done in the setup_env() part of the script but wasn't"
      exit 1
    fi

    case "$KOKKOS_BACKEND" in
      CUDA)

        if ! [[ "$COMPILER" =~ gcc-8* ]]; then
          echo "Model '$MODEL' can only be used with compilers: gcc-8*."
          exit 3
        fi

        NVCC_BIN="$KOKKOS_DIR/bin/nvcc_wrapper"
        MAKE_OPTS+=" -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=$NVCC_BIN"
        MAKE_OPTS+=" -DKokkos_ENABLE_CUDA_LAMBDA=ON"
        # MAKE_OPTS+=" -DCMAKE_VERBOSE_MAKEFILE=ON"
        ;;
      OPENMP)
        case "$COMPILER" in
        aocc-*|llvm-*)
          MAKE_OPTS+=" -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++"
          ;;
        arm-*)
          MAKE_OPTS+=" -DCMAKE_C_COMPILER=armclang -DCMAKE_CXX_COMPILER=armclang++"
          ;;
        cce-*)
          module load gcc/8.2.0 >/dev/null || module load gcc/8.1.0 # this is only for libstdc++, the compilers are still CC
          MAKE_OPTS+=" -DCMAKE_C_COMPILER=cc -DCMAKE_CXX_COMPILER=CC"
          ;;
        gcc-*)
          MAKE_OPTS+=" -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++"
          ;;
        intel-*)
          MAKE_OPTS+=" -DCMAKE_C_COMPILER=icc -DCMAKE_CXX_COMPILER=icpc"
          ;;
        *)
          echo "Cannot use '$COMPILER' with Kokkos."
          usage
          exit 1
          ;;
        esac
        ;;
      HIP)
        if ! [[ "$COMPILER" =~ hipcc* ]]; then
          echo "Model '$MODEL' can only be used with hipcc"
          exit 3
        fi
        MAKE_OPTS+=" -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=hipcc"
        ;;
      OPENMPTARGET)
        MAKE_OPTS+=" -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx"
        ;;
      *)
        echo "Unsupported '$KOKKOS_ARCH', implement the correct compiler for me."
        usage
        exit 1
    esac


    ;;
  sycl)
    if [ ! -e cloverleaf_sycl/CMakeLists.txt ]; then
      git clone -b sycl-history "https://github.com/UoB-HPC/cloverleaf_sycl"
    fi
    export SRC_DIR="$PWD/cloverleaf_sycl"
    USE_CMAKE=true
    ;;

  *)
    echo
    echo "Invalid model '$MODEL'."
    usage
    exit 1
    ;;
esac

export RUN_DIR="$SRC_DIR"



# Handle actions
if [ "$action" == "build" ]; then

  cd "$SRC_DIR" || exit 1

  rm -f "$BENCHMARK_EXE"
  if [ "$USE_CMAKE" = true ]; then

    read -ra CMAKE_OPTS <<<"${MAKE_OPTS}" # explicit word splitting
    if [ "$MODEL" = kokkos ] && [ -n "$KOKKOS_EXTRA_FLAGS" ]; then
      CMAKE_OPTS+=("-DCXX_EXTRA_FLAGS=$KOKKOS_EXTRA_FLAGS")
    fi
    echo "Using opts: ${CMAKE_OPTS[@]} was ${MAKE_OPTS}"

    rm -rf build
    cmake -Bbuild -H. -DCMAKE_BUILD_TYPE=Release "${CMAKE_OPTS[@]}"
    cmake --build build --target clover_leaf --config Release -j "$(nproc)"
    mv "build/$BINARY" "$BENCHMARK_EXE"

  else
    make clean
    if ! eval make -B "$MAKE_OPTS" -j; then
      echo
      echo "Build failed."
      echo
      exit 1
    fi
    mv "$BINARY" "$BENCHMARK_EXE"
  fi
elif [ "$action" == "run" ]; then

  # Check binary exists
  if [ ! -x "$SRC_DIR/$BENCHMARK_EXE" ]; then
    echo "Executable '$BENCHMARK_EXE' not found."
    echo "Use the 'build' action first."
    exit 1
  fi
  if [ "$USE_QUEUE" = true ]; then
    pwd
    qsub -o "$PWD/cloverleaf-$CONFIG.out" -N "cloverleaf-$CONFIG" -V "$SCRIPT_DIR/run.job"
  else
    bash $SCRIPT_DIR/run.job &> "cloverleaf-$CONFIG.out"
  fi

else
  echo
  echo "Invalid action (use 'build' or 'run')."
  echo
  exit 1
fi
