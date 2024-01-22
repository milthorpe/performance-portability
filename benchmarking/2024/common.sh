#!/bin/bash

set -eu

prime_chapel() {
  echo "Not yet implemented"
}

prime_kokkos() {
  KOKKOS_VER="4.2.00"
  KOKKOS_DIR="$SRC_DIR/kokkos-$KOKKOS_VER"

  echo "Using Kokkos src $KOKKOS_DIR"

  if [ ! -e "$KOKKOS_DIR" ]; then
    git clone --branch cmake --depth 1 https://github.com/milthorpe/kokkos.git $KOKKOS_DIR
  fi
  export KOKKOS_DIR="$KOKKOS_DIR"
}

load_nvhpc() {
  VERSION=${1:-23.11}
  if grep -q "Amazon Linux" "/etc/os-release"; then
    # use spack
    export NVHPC_PATH
    spack load nvhpc@${VERSION}
    NVHPC_PATH=$(realpath "$(dirname "$(which nvc++)")/../../")
  else
    module load nvhpc/${VERSION}
    if [ ! -d "$NVHPC_ROOT" ]; then
      echo "NVHPC_ROOT '$NVHPC_ROOT' is not a directory"
      exit 2
    fi
  fi
}

load_oneapi() {
  if [ -z "${1:-}" ]; then
    echo "${FUNCNAME[0]}: Usage: ${FUNCNAME[0]} /path/to/oneapi/source.sh"
    echo "No OneAPI path provided. Stop."
    exit 5
  fi

  local oneapi_env="${1}"

  set +u                           # setvars can't handle unbound vars
  CURRENT_SCRIPT_DIR="$SCRIPT_DIR" # save current script dir as the setvars overwrites it

  # their script also terminates the shell for some reason so we short-circuit it first
  source "$oneapi_env" --force || true

  set -u
  SCRIPT_DIR="$CURRENT_SCRIPT_DIR" #recover script dir
}

check_vars() {
  local var_names=("$@")
  for var_name in "${var_names[@]}"; do
    [ -z "${!var_name}" ] && echo "$var_name is unset." && var_unset=true
  done
  [ -n "${var_unset:-}" ] && exit 1
  return 0
}

check_bin() {
  if [ ! -f "$1" ]; then # we got Julia which is text, so no -x
    echo "Executable '$1' not found."
    echo "Use the 'build' action first."
    exit 1
  fi
}

unknown_compiler() {
  echo "Invalid compiler '$COMPILER'."
  exit 1
}

unknown_model() {
  echo "Invalid model '$MODEL'."
  exit 1
}

handle_cmd() {

  check_vars 1 2 3 4 5

  local action=$1
  local compiler=$2
  local model=$3
  local name=$4
  local config=$5

  export ACTION="$action"
  export COMPILER="$compiler"
  export MODEL="$model"

  export CONFIG="${config}_${compiler}_${model}"
  export BENCHMARK_NAME="$name-$CONFIG"
  export RUN_DIR="$PWD/$name-$CONFIG"

}

append_opts() {
  if [ "$#" -ne 1 ]; then
    echo "${FUNCNAME[0]}: illegal number of parameters, expecting 1 but got $# "
  fi
  MAKE_OPTS="${MAKE_OPTS:-} $1"
}

handle_exec() {

  check_vars ACTION CONFIG BENCHMARK_NAME RUN_DIR MODEL MAKE_OPTS BENCHMARK_EXE

  if [ ! -d "$SRC_DIR" ]; then
    echo "Source dir '$SRC_DIR' does not exist"
    exit 2
  fi

  local src
  src="$RUN_DIR/$(basename "$SRC_DIR")"

  # Handle actions
  if [ "$ACTION" == "build" ]; then

    rm -f "$RUN_DIR/$BENCHMARK_EXE"
    mkdir -p "$RUN_DIR"

    rsync -rvq --exclude=.git "$SRC_DIR" "$RUN_DIR"

    echo "[$ACTION] Copied '$SRC_DIR' source to '$src'"

    cd "$src"

    if [ "$USE_MAKE" = true ]; then
      echo "[$ACTION] Using make opts: $MAKE_OPTS"
      make -C src/$MODEL clean "$MAKE_OPTS"
      eval make -C src/$MODEL -B -j "$(nproc)" "$MAKE_OPTS"
      ldd "$src/src/$MODEL/$BENCHMARK_EXE"
    else
      read -ra CMAKE_OPTS <<<"${MAKE_OPTS}" # explicit word splitting
      echo "[$ACTION] Using cmake opts:" "${CMAKE_OPTS[@]}"
      rm -rf build
      cmake -Bbuild -H. -DCMAKE_BUILD_TYPE=RELEASE "${CMAKE_OPTS[@]}"
      cmake --build build --config RELEASE -j "$(nproc)"
      ldd "$src/build/$BENCHMARK_EXE"
    fi

  elif [ "$ACTION" == "run" ] || [ "$ACTION" == "run-scale" ]; then

    if [ "$USE_MAKE" = true ]; then
      export BENCHMARK_EXE="${src}/src/${MODEL}/${BENCHMARK_EXE}"
    else
      export BENCHMARK_EXE="$src/build/$BENCHMARK_EXE"
    fi
    check_bin "$BENCHMARK_EXE"

    if [ "$ACTION" == "run" ]; then
      local job="$SCRIPT_DIR/run.job"
      local name="$BENCHMARK_NAME"
    elif [ "$ACTION" == "run-scale" ]; then
      local job="$SCRIPT_DIR/run-scale.job"
      local name="scale_$BENCHMARK_NAME"
    else
      echo
      echo "Invalid action: $ACTION"
      exit 1
    fi

    export OUT_FILE="$PWD/$name".out0
    echo "[$ACTION] Submitting '$job'"

    if [ "${USE_SLURM:-}" = true ]; then
      queue_cmd="sbatch"
    else
      queue_cmd="qsub"
    fi

    if [ -x "$(command -v $queue_cmd)" ]; then
      if [ "${USE_SLURM:-}" = true ]; then
        sbatch --output "$name".out -J "$name" "$job"
      else
        qsub -o "$name".out -N "$name" -V "$job"
      fi
      retval=$?
    else
      echo "No queue, starting local exec: $name"
      : >"$OUT_FILE"
      set +e # don't fail on non-zero exit
      bash "$job" &> >(tee -a "$OUT_FILE")
      retval=$?
      set -e # restore
      if [ $retval -ne 0 ]; then
        echo "$name failed!"
      else
        echo "$name complete."
      fi
    fi

  else

    echo
    echo "Invalid action: $ACTION"
    exit 1
  fi
  if [ $retval -ne 0 ]; then
    echo "[$ACTION] failed!"
  else
    echo "[$ACTION] Complete!"
  fi
}
