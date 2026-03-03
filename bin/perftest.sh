#!/bin/bash
# Generate perftest (ib_write_bw, ib_read_bw, ib_read_lat) commands
# for all combinations, ready to copy-paste into server and client terminals.

set -e

PORT=18001

usage() {
  echo "Usage: $0 -r <remote_host> -l <local_device> -d <remote_device> [-b cuda|rocm] [-g <gpu_device>] [-t <perftest_dir>]"
  echo ""
  echo "  -r  Remote hostname (e.g. gputest-genoa-02)"
  echo "  -l  Local IB device  (e.g. mlx5_3)"
  echo "  -d  Remote IB device (e.g. mlx5_4)"
  echo "  -b  GPU backend: cuda or rocm (default: cuda)"
  echo "  -g  GPU device index for server (default: 1)"
  echo "  -t  Absolute path to perftest binaries (default: use PATH)"
  echo ""
  echo "Example:"
  echo "  $0 -r gputest-genoa-02 -l mlx5_3 -d mlx5_4"
  echo "  $0 -r gputest-genoa-02 -l mlx5_3 -d mlx5_4 -b rocm -g 0 -t /opt/perftest/bin"
  exit 1
}

BACKEND="cuda"
GPU_DEV=1
PERFTEST_DIR=""

while getopts "r:l:d:b:g:t:h" opt; do
  case $opt in
    r) REMOTE_HOST="$OPTARG" ;;
    l) LOCAL_DEV="$OPTARG" ;;
    d) REMOTE_DEV="$OPTARG" ;;
    b) BACKEND="$OPTARG" ;;
    g) GPU_DEV="$OPTARG" ;;
    t) PERFTEST_DIR="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [ -z "$REMOTE_HOST" ] || [ -z "$LOCAL_DEV" ] || [ -z "$REMOTE_DEV" ]; then
  echo "Error: -r, -l, and -d are required."
  echo ""
  usage
fi

BACKEND=$(echo "$BACKEND" | tr '[:upper:]' '[:lower:]')
case "$BACKEND" in
  cuda)
    GPU_FLAGS="--use_cuda=$GPU_DEV --use_cuda_dmabuf"
    ;;
  rocm)
    GPU_FLAGS="--use_rocm=$GPU_DEV --use_rocm_dmabuf"
    ;;
  *)
    echo "Error: unknown backend '$BACKEND'. Use 'cuda' or 'rocm'."
    exit 1
    ;;
esac

TESTS=("ib_write_bw" "ib_read_bw" "ib_read_lat")

# Build binary prefix: if PERFTEST_DIR is set, use it; otherwise rely on PATH
if [ -n "$PERFTEST_DIR" ]; then
  BIN_PREFIX="${PERFTEST_DIR%/}/"
else
  BIN_PREFIX=""
fi

for TEST in "${TESTS[@]}"; do
  echo "------------------------------------------------------------"
  echo " $TEST"
  echo ""
  echo "# SERVER ($REMOTE_HOST):"
  echo "${BIN_PREFIX}$TEST -d $REMOTE_DEV -F --report_gbits -a $GPU_FLAGS -p $PORT"
  echo ""
  echo "# CLIENT:"
  echo "${BIN_PREFIX}$TEST -d $LOCAL_DEV -F --report_gbits -a -p $PORT $REMOTE_HOST"
  echo ""

  # PORT=$((PORT + 1))
done
