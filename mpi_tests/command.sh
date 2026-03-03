set -ex


BIN="./main HtoD"
UCX_NET_DEVICES_R0=mlx5_3:1
UCX_NET_DEVICES_R1=mlx5_4:1
UCX_TLS=rc,cuda
UCX_TLS=rc,cuda
UCX_TLS=rc,cuda_copy,gdr_copy,sm

# EXTRA_UCX_OPTS="-x UCX_MEMTYPE_CACHE=n -x UCX_RNDV_THRESH=inf -x UCX_RNDV_SCHEME=put_ppln -x UCX_IB_GPU_DIRECT_RDMA=yes -x UCX_IB_GID_INDEX=3 -x UCX_IB_REG_METHODS=dmabuf"
EXTRA_UCX_OPTS="-x UCX_IB_GPU_DIRECT_RDMA=yes"


MPIRUN="cmsenv_mpirun --mca oob_tcp_if_exclude enp4s0f4u1u2c2"

$MPIRUN -x UCX_PROTO_INFO=y -x UCX_LOG_LEVEL=info --map-by node --tag-output --mca pml ucx -x UCX_TLS=$UCX_TLS $EXTRA_UCX_OPTS \
-np 1 --host gputest-milan-02 -x CUDA_VISIBLE_DEVICES= -x UCX_NET_DEVICES=$UCX_NET_DEVICES_R0  $BIN : \
-np 1 --host gputest-genoa-02 -x CUDA_VISIBLE_DEVICES=1 -x HIP_VISIBLE_DEVICES= -x UCX_NET_DEVICES=$UCX_NET_DEVICES_R1  $BIN

