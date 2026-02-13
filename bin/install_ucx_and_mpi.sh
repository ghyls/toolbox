#!/bin/bash
set -ex

UCX_VERSION="1.20.0"
OMPI_VERSION="5.0.9"
INSTALL_PREFIX=/shared/custom_ucx_and_mpi
ROCM_PATH=/opt/rocm
THREADS=$(nproc)

mkdir -p $INSTALL_PREFIX
cd /tmp

wget https://github.com/openucx/ucx/releases/download/v${UCX_VERSION}/ucx-${UCX_VERSION}.tar.gz
tar -xvf ucx-${UCX_VERSION}.tar.gz
cd ucx-${UCX_VERSION}

./configure \
    --prefix=${INSTALL_PREFIX}/ucx \
    --with-rocm=${ROCM_PATH} \
    --with-verbs \
    --without-go \
    --without-knem \
    --enable-mt \
    --enable-optimizations \
    --disable-logging \
    --disable-debug \
    --disable-assertions

make -j ${THREADS}
make install
cd ..

wget https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-${OMPI_VERSION}.tar.gz
tar -xvf openmpi-${OMPI_VERSION}.tar.gz
cd openmpi-${OMPI_VERSION}

./configure \
    --prefix=${INSTALL_PREFIX}/openmpi \
    --with-ucx=${INSTALL_PREFIX}/ucx \
    --with-rocm=${ROCM_PATH} \
    --with-pmix=internal \
    --with-prrte=internal

make -j ${THREADS}
make install

cat <<EOF > ${INSTALL_PREFIX}/setup_env.sh
export PATH=${INSTALL_PREFIX}/openmpi/bin:${INSTALL_PREFIX}/ucx/bin:\$PATH
export LD_LIBRARY_PATH=${INSTALL_PREFIX}/openmpi/lib:${INSTALL_PREFIX}/ucx/lib:${ROCM_PATH}/lib:\$LD_LIBRARY_PATH
export UCX_ROCM_COPY_LATENCY=0
export UCX_IB_REG_METHODS=dmabuf
export UCX_TLS=rc,sm,rocm_copy,rocm_ipc
EOF

echo "Done! Run 'source ${INSTALL_PREFIX}/setup_env.sh'"