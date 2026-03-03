#!/bin/bash
set -ex

UCX_VERSION="1.20.0"
OMPI_VERSION="5.0.9"
INSTALL_PREFIX=/data/user/mario/sw/test
SRC_DIR=/data/user/mario/sw/test/src
HIPCC=$(command -v hipcc 2>/dev/null || true)
NVCC=$(command -v nvcc 2>/dev/null || true)
ROCM_PATH=${ROCM_PATH:-${HIPCC%/bin/hipcc}}
CUDA_PATH=${CUDA_PATH:-${NVCC%/bin/nvcc}}
ENABLE_CUDA=1
ENABLE_ROCM=0
THREADS=$(nproc)

if [[ ${ENABLE_CUDA} -eq 1 && -z ${CUDA_PATH} ]]; then
    echo "ERROR: ENABLE_CUDA=1 but nvcc not found and CUDA_PATH not set" >&2
    exit 1
fi

if [[ ${ENABLE_ROCM} -eq 1 && -z ${ROCM_PATH} ]]; then
    echo "ERROR: ENABLE_ROCM=1 but hipcc not found and ROCM_PATH not set" >&2
    exit 1
fi

mkdir -p $INSTALL_PREFIX
mkdir -p $SRC_DIR
cd $SRC_DIR

wget https://github.com/openucx/ucx/releases/download/v${UCX_VERSION}/ucx-${UCX_VERSION}.tar.gz
tar -xvf ucx-${UCX_VERSION}.tar.gz
cd ucx-${UCX_VERSION}

./configure \
    --prefix=${INSTALL_PREFIX}/ucx \
    --with-verbs \
    --with-gdrcopy \
    --with-rdmacm \
    --with-rc \
    --with-dc \
    --with-dm \
    --without-go \
    --without-knem \
    --enable-mt \
    --enable-optimizations \
    --disable-logging \
    --disable-debug \
    --disable-assertions \
    $( [[ ${ENABLE_CUDA} -eq 1 && -n ${CUDA_PATH} ]] && echo "--with-cuda=${CUDA_PATH}" || echo "--without-cuda" ) \
    $( [[ ${ENABLE_ROCM} -eq 1 && -n ${ROCM_PATH} ]] && echo "--with-rocm=${ROCM_PATH}" || echo "--without-rocm" )

make -j ${THREADS}
make install
cd ..

# wget https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-${OMPI_VERSION}.tar.gz
# tar -xvf openmpi-${OMPI_VERSION}.tar.gz
# cd openmpi-${OMPI_VERSION}
#
# ./configure \
#     --prefix=${INSTALL_PREFIX}/openmpi \
#     --with-ucx=${INSTALL_PREFIX}/ucx \
#     --with-pmix=internal \
#     --with-prrte=internal \
#     $( [[ ${ENABLE_CUDA} -eq 1 && -n ${CUDA_PATH} ]] && echo "--with-cuda=${CUDA_PATH}" || echo "--without-cuda" ) \
#     $( [[ ${ENABLE_ROCM} -eq 1 && -n ${ROCM_PATH} ]] && echo "--with-rocm=${ROCM_PATH}" || echo "--without-rocm" )
#
# make -j ${THREADS}
# make install

cat <<EOF > ${INSTALL_PREFIX}/setup_env.sh
export PATH=${INSTALL_PREFIX}/openmpi/bin:${INSTALL_PREFIX}/ucx/bin:\$PATH
ROCM_LIB_PATH=${ROCM_PATH:+${ROCM_PATH}/lib}
export LD_LIBRARY_PATH=${INSTALL_PREFIX}/openmpi/lib:${INSTALL_PREFIX}/ucx/lib:$( [[ ${ENABLE_ROCM} -eq 1 && -n ${ROCM_LIB_PATH} ]] && echo "${ROCM_LIB_PATH}:" )\$LD_LIBRARY_PATH
export UCX_ROCM_COPY_LATENCY=0
export UCX_IB_REG_METHODS=dmabuf
export UCX_TLS=rc,sm$( [[ ${ENABLE_ROCM} -eq 1 && -n ${ROCM_PATH} ]] && echo ",rocm_copy,rocm_ipc" )
EOF

echo "Done! Run 'source ${INSTALL_PREFIX}/setup_env.sh'"
