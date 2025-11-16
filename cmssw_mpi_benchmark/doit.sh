#!/bin/bash
set -e

# config takes threads and streams as environment variables: EXPERIMENT_THREADS and EXPERIMENT_STREAMS


thread_stream_pairs=("8 6" "16 12" "24 18" "32 24")
nRuns=6

log_dir="./logs"

ucx_tls="rc,cuda_copy,cuda_ipc,gdr_copy,sm,self"

host_local="gputest-milan-02"
host_remote="gputest-genoa-02"


# Options
isngt=false


mkdir -p $log_dir


# single process
run_benchmark_1p() {
    local tag=$1
    local config=$2
    local first_cpu=$3

    for pair in "${thread_stream_pairs[@]}"; do
        threads=$(echo $pair | cut -d' ' -f1)
        streams=$(echo $pair | cut -d' ' -f2)

        last_cpu=$((first_cpu + threads - 1))

        for run_id in $(seq 1 $nRuns); do
            echo "Running local benchmark with $threads threads and $streams streams, run $run_id"

            logfile="$log_dir/${tag}_t${threads}_s${streams}_r${run_id}.log"

            cmd="EXPERIMENT_THREADS=$threads EXPERIMENT_STREAMS=$streams numactl --physcpubind=$first_cpu-$last_cpu cmsRun  $config > $logfile 2>&1"
            echo "Running command: $cmd"
            echo "Logging to: $logfile"
            eval $cmd
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

            if [ "$mpi_impl" == "ompi" ]; then
                cmd+=(--mca pml ucx -x UCX_TLS=$ucx_tls)
            else
                cmd+=(-genv UCX_TLS=$ucx_tls)
            fi

            if [[ "$isSameHost" = false && "$mpi_impl" == "mpich" ]]; then
                cmd+=(-hosts "$host_local,$host_remote")
            fi


            if [[ "$isSameHost" == false && "$mpi_impl" == "ompi" ]]; then
                cmd+=(--mca oob_tcp_if_exclude enp4s0f4u1u2c2)
            fi

            if [ "$mpi_impl" == "ompi" ]; then
                cmd+=(-x EXPERIMENT_THREADS=$threads -x EXPERIMENT_STREAMS=$streams)
            else
                cmd+=(-env EXPERIMENT_THREADS $threads -env EXPERIMENT_STREAMS $streams)
            fi

            cmd+=(-np 1)

            if [[ "$isSameHost" = false && "$mpi_impl" == "ompi" ]]; then
                cmd+=(--host $host_local)
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








# Milan-Genoa OpenMPI
# -----------------------------------

# # local test
# config=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_test.py
# run_benchmark_1p $config 32

# # local-local test
# config_local=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_local.py
# config_remote=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_remote.py
# run_benchmark_2p "milan_milan_ompi" "ompi" $config_local $config_remote 0 32 true

# # local-remote test
# config_local=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_local.py
# config_remote=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_remote.py
# run_benchmark_2p "milan_genoa_ompi" "ompi" $config_local $config_remote 32 48 true


# Milan-Genoa MPICH
# -----------------------------------

# # local test
# config=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_test.py
# run_benchmark_1p "milan" $config 32

# local-local test
config_local=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_local.py
config_remote=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_remote.py
run_benchmark_2p "milan_milan_ompi" "mpich" $config_local $config_remote 0 32 true

# # local-remote test
# config_local=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_local.py
# config_remote=/data/user/mario/sw/cmssw/anna-cmssw/CMSSW_16_0_0_pre1/src/HeterogeneousCore/MPICore/test/test_scripts_and_configs/real/hlt_remote.py
# run_benchmark_2p "milan_genoa_ompi" "mpich" $config_local $config_remote 32 48 true







