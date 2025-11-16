#!/bin/bash
set -e

# config takes threads and streams as environment variables: EXPERIMENT_THREADS and EXPERIMENT_STREAMS


thread_stream_pairs=("8 6" "16 12" "24 18" "32 24")
# thread_stream_pairs=("24 24") 

nRuns=6

log_dir="./logs"

ucx_tls="rc,cuda_copy,cuda_ipc,gdr_copy,sm,self"

host_local="gputest-milan-02"
host_remote="gputest-genoa-02"


ompi_ssh_agent_path="/eos/home-i03/m/mariogo/toolbox/cmssw_mpi_benchmark/env_ompi_kubexec.sh"

isngt=$1

if [ -z "$isngt" ]; then
    echo "Usage: $0 <isngt:true|false>"
    exit 1
fi

mkdir -p $log_dir


# single process
run_benchmark_1p() {
    local tag=$1
    local config=$2
    local first_cpu=$3

    if [ "$isngt" == true ]; then
        source ~/ngt-farm/scripts/setup_env.sh
    fi

    for pair in "${thread_stream_pairs[@]}"; do
        threads=$(echo $pair | cut -d' ' -f1)
        streams=$(echo $pair | cut -d' ' -f2)

        if [[ "$isngt" == true && $threads -gt 31 ]]; then
            # we only have 31 physical cores per NUMA on NGT nodes
            threads=31
        fi

        last_cpu=$((first_cpu + threads - 1))

        for run_id in $(seq 1 $nRuns); do
            echo "Running local benchmark with $threads threads and $streams streams, run $run_id"
            echo "Binding to CPUs: $first_cpu-$last_cpu"

            logfile="$log_dir/${tag}_t${threads}_s${streams}_r${run_id}.log"

            cmd=(env EXPERIMENT_THREADS=$threads EXPERIMENT_STREAMS=$streams)

            if [[ "$isngt" = true ]]; then
                # cmd+=(numactl --cpunodebind=0 --membind=0 taskset -c 0-$((threads-1)))
                cmd+=(numactl --physcpubind=$first_cpu-$last_cpu)
            else
                cmd+=(numactl --physcpubind=$first_cpu-$last_cpu)
            fi

            cmd+=(cmsRun $config)



            echo "Running command: ${cmd[*]}"
            echo "Logging to: $logfile"
            "${cmd[@]}" > $logfile 2>&1

            cat $logfile | grep throughput
        done
    done
}

# 2 processes
run_benchmark_2p() {
    local tag=$1
    local mpi_impl=$2
    local config_local=$3
    local config_remote=$4
    local first_cpu_local=$5
    local first_cpu_remote=$6
    local isSameHost=$7

    if [ "$mpi_impl" == "ompi" ]; then
        echo "Using OpenMPI"
    elif [ "$mpi_impl" == "mpich" ]; then
        echo "Using MPICH"
    else
        echo "Unknown MPI implementation: $mpi_impl"
        exit 1
    fi


    for pair in "${thread_stream_pairs[@]}"; do
        threads=$(echo $pair | cut -d' ' -f1)
        streams=$(echo $pair | cut -d' ' -f2)

        if [[ "$isngt" == true && $threads -gt 29 ]]; then
            # we only have 29 physical cores per NUMA on NGT nodes
            threads=29
        fi

        last_cpu_local=$((first_cpu_local + threads - 1))
        last_cpu_remote=$((first_cpu_remote + threads - 1))

        for run_id in $(seq 1 $nRuns); do
            echo "Running benchmark with $threads threads and $streams streams, run $run_id"
            logfile="$log_dir/${tag}_t${threads}_s${streams}_r${run_id}.log"


            echo "Local CPUs: $first_cpu_local-$last_cpu_local"
            echo "Remote CPUs: $first_cpu_remote-$last_cpu_remote"



            cmd=()  # this is going to be painful

            if [ "$isngt" = true ]; then
                cmd+=(mpirun)
            else
                cmd+=(cmsenv_mpirun)
            fi

            if [[ "$isngt" == true && "$mpi_impl" == "ompi" ]]; then
                cmd+=(--hostfile /etc/mpi/hostfile)
                cmd+=(--prtemca plm_ssh_agent $ompi_ssh_agent_path)
            fi


            if [ "$mpi_impl" == "ompi" ]; then
                cmd+=(--mca pml ucx -x UCX_TLS=$ucx_tls)
            else
                cmd+=(-genv UCX_TLS=$ucx_tls)
            fi

            if [[ "$isSameHost" == false && "$mpi_impl" == "mpich" ]]; then
                cmd+=(-hosts "$host_local,$host_remote")
            fi


            if [[ "$isSameHost" == false && "$mpi_impl" == "ompi" ]]; then
                cmd+=(--mca oob_tcp_if_exclude enp4s0f4u1u2c2)
            fi

            if [ "$mpi_impl" == "ompi" ]; then
                cmd+=(-x EXPERIMENT_THREADS=$threads -x EXPERIMENT_STREAMS=$streams)
            else
                cmd+=(-genv EXPERIMENT_THREADS $threads -genv EXPERIMENT_STREAMS $streams)
            fi

            cmd+=(-np 1)

            if [[ "$isSameHost" = false && "$mpi_impl" == "ompi" ]]; then
                cmd+=(--host $host_local)
            fi

            if [ "$isSameHost" == false ]; then
                if [ "$mpi_impl" == "ompi" ]; then
                    cmd+=(-x UCX_NET_DEVICES=mlx5_2:1)
                else
                    cmd+=(-env UCX_NET_DEVICES mlx5_2:1)
                fi
            fi


            if [ "$mpi_impl" == "ompi" ]; then
                cmd+=(-bind-to none)
            fi
            cmd+=(numactl --physcpubind=$first_cpu_local-$last_cpu_local)
            cmd+=(cmsRun $config_local)

            cmd+=(:)

            cmd+=(-np 1)

            if [[ "$isSameHost" = false && "$mpi_impl" == "ompi" ]]; then
                cmd+=(--host $host_remote)
            fi

            if [ "$isSameHost" == false ]; then
                if [ "$mpi_impl" == "ompi" ]; then
                    cmd+=(-x UCX_NET_DEVICES=mlx5_0:1)
                else
                    cmd+=(-env UCX_NET_DEVICES mlx5_0:1)
                fi
            fi

            if [ "$mpi_impl" == "ompi" ]; then
                cmd+=(-bind-to none)
            fi
            cmd+=(numactl --physcpubind=$first_cpu_remote-$last_cpu_remote)
            cmd+=(cmsRun $config_remote)


            echo "Running command: ${cmd[*]}"
            echo "Logging to: $logfile"
            # echo output an errors to logfile
            "${cmd[@]}" > $logfile 2>&1
            cat $logfile | grep throughput
        done
    done
}








if [ "$isngt" == false ]; then

    echo "Running on Milan-Genoa"

    # Milan-Genoa OpenMPI
    # -----------------------------------

    # local test
    config=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_test.py
    run_benchmark_1p "milan" $config 32

    # local-local test
    config_local=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_local.py
    config_remote=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_remote.py
    run_benchmark_2p "milan_milan_ompi" "ompi" $config_local $config_remote 0 32 true

    # local-remote test
    config_local=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_local.py
    config_remote=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_remote.py
    run_benchmark_2p "milan_genoa_ompi" "ompi" $config_local $config_remote 32 48 false


    # Milan-Genoa MPICH
    # -----------------------------------

    # # local test
    # config=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_test.py
    # run_benchmark_1p "milan_2lumiblocks" $config 32

    # # local-local test
    # config_local=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_local.py
    # config_remote=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_remote.py
    # run_benchmark_2p "milan_milan_mpich" "mpich" $config_local $config_remote 0 32 true

    # local-remote test
    config_local=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_local.py
    config_remote=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_remote.py
    run_benchmark_2p "milan_genoa_mpich_tmp" "mpich" $config_local $config_remote 32 48 false


else

    echo "Running on the NGT farm"

    # NGT H100 H100 IB400G OpenMPI
    # -----------------------------------

    # # local test
    # config=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_test.py
    # run_benchmark_1p "ngt_h100_ompi" $config 32

    # # local-local test
    # config_local=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_local.py
    # config_remote=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_remote.py
    # run_benchmark_2p "ngt_h100_h100_ib400G_ompi" "ompi" $config_local $config_remote 0 32 true

    # # local-remote test
    config_local=/shared/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_local.py
    config_remote=/shared/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_remote.py
    # run_benchmark_2p "ngt_h100_h100_ib400_ompi" "ompi" $config_local $config_remote 32 48 false


    # NGT H100 H100 IB400G MPICH
    # -----------------------------------

    # # local test
    # config=/shared/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_test.py
    # # config=/scratch/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_test.py
    # run_benchmark_1p "ngt_h100" $config 32

    # # local-local test
    # config_local=/shared/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_local.py
    # config_remote=/shared/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_remote.py
    # run_benchmark_2p "ngt_h100_h100_ib400G_mpich" "mpich" $config_local $config_remote 0 32 true

    # # local-remote test
    # config_local=/shared/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_local.py
    # config_remote=/shared/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_remote.py
    # run_benchmark_2p "ngt_h100_h100_self_mpich" "mpich" $config_local $config_remote 1 1 true

fi
