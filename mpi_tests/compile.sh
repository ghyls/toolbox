#!/bin/bash
# Exit on error
set -ex

# Check for backend argument
if [ $# -ne 1 ]; then
  echo "Error: Backend argument required. Usage: $0 {cuda|rocm}" >&2
  exit 1
fi

BACKEND=$(echo "$1" | tr '[:upper:]' '[:lower:]')

# Detect MPI installation path
MPICXX_PATH=$(which mpicxx 2>/dev/null)
if [ -z "$MPICXX_PATH" ]; then
  echo "Error: mpicxx not found in PATH. Please install MPI or set PATH correctly." >&2
  exit 1
fi
MPI_BASE=$(dirname $(dirname "$MPICXX_PATH"))

SOURCE="doit.cpp"
OUTPUT="main"

if [ "$BACKEND" = "cuda" ]; then
  NVCC_PATH=$(which nvcc 2>/dev/null)
  if [ -z "$NVCC_PATH" ]; then
    echo "Error: nvcc not found in PATH." >&2
    exit 1
  fi
  CUDA_BASE=$(dirname $(dirname "$NVCC_PATH"))
  
  g++ -o "$OUTPUT" "$SOURCE" \
    -DUSE_CUDA \
    -I"${MPI_BASE}/include" \
    -I"${CUDA_BASE}/include" \
    -L"${MPI_BASE}/lib" \
    -L"${CUDA_BASE}/lib64" \
    -std=c++20 \
    -lmpi \
    -lcudart \
    -lpthread \
    -Wl,-rpath,"${MPI_BASE}/lib" \
    -Wl,-rpath,"${CUDA_BASE}/lib64"

elif [ "$BACKEND" = "rocm" ]; then
  HIPCC_PATH=$(which hipcc 2>/dev/null)
  if [ -z "$HIPCC_PATH" ]; then
    echo "Error: hipcc not found in PATH." >&2
    exit 1
  fi
  ROCM_BASE=$(dirname $(dirname "$HIPCC_PATH"))
  
  g++ -o "$OUTPUT" "$SOURCE" \
    -DUSE_ROCM \
    -I"${MPI_BASE}/include" \
    -I"${ROCM_BASE}/include" \
    -L"${MPI_BASE}/lib" \
    -L"${ROCM_BASE}/lib" \
    -std=c++20 \
    -lmpi \
    -lamdhip64 \
    -lpthread \
    -Wl,-rpath,"${MPI_BASE}/lib" \
    -Wl,-rpath,"${ROCM_BASE}/lib"

else
  echo "Error: Invalid backend '$1'. Use 'cuda' or 'rocm'" >&2
  exit 1
fi
