


import re
import os
import subprocess
import sys



# switch on/off each test
# options common to all tests are set directly in main()
RUN_MILAN_STANDALONE_CPUONLY =  False
RUN_MILAN_STANDALONE =          False
RUN_MILAN_MILAN_CPUONLY =       False
RUN_MILAN_MILAN =               False
RUN_MILAN_GENOA_CPUONLY =       False
RUN_MILAN_GENOA =               False

RUN_NGT_STANDALONE_CPUONLY =    False
RUN_NGT_STANDALONE =            False
RUN_NGT_NGT_XSOCKET_CPUONLY =   False
RUN_NGT_NGT_XSOCKET =           False
RUN_NGT_NGT_CPUONLY =           True
RUN_NGT_NGT =                   True




# config common to all benchmarks on a single run
class GlobalConfig:
    # Common MPI implementation for all configs
    mpi_impl = ""

    # Print the command but not run
    print_cmd_no_run = True

    runID = 0

    # Run just the first t,s pair of the list and move to the next setup
    run_first_ts_pair_only = False

    log_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)


# Config describing each test (set for e.g. Milan, Milan-Milan, Milan-Genoa, NGT, etc.)
class Config(GlobalConfig):

    environment = ""
    ts = [0, 0]

    host_local = ""
    host_remote = ""
    is_same_machine = False
    ucx_tls = "all"
    ucx_net_devices_local = ""
    ucx_net_devices_remote = ""
    
    config_local = ""
    config_remote = ""

    cpus_local = []
    cpus_remote = []
    cuda_visible_devices_local = "all"
    cuda_visible_devices_remote = "all"

    label = ""

    def validate(self):
        if self.environment not in ["HLT", "NGT", "NGT-MPI"]:
            print("Unknown environment configuration:", self.environment)
            sys.exit(1)
        if self.config_local != "" and self.config_remote != "":
            # if using MPI
            print("config_local and config_remote are set. using MPI!")
            if self.mpi_impl not in ["OpenMPI", "MPICH"]:
                print("Unknown mpi_impl %s. Supported are OpenMPI and MPICH" % self.mpi_impl)
                sys.exit(1)
            if not os.path.isfile(self.config_local) or not os.path.isfile(self.config_remote):
                print("Local or remote config file does not exist.")
                sys.exit(1)
            if len(self.cpus_local) == 0 or len(self.cpus_remote) == 0:
                print("cpus_local or cpus_remote not set.")
                sys.exit(1)
            
        elif self.config_local != "":
            # plain good old cmsRun without MPI
            if not os.path.isfile(self.config_local):
                print("config_local file %s does not exist." % self.config_local)
                sys.exit(1)
            if len(self.cpus_local) == 0:
                print("cpus_local not set.")
                sys.exit(1)
        else:
            print("Either [config_local and config_remote] or just [config_local] must be set.")
            sys.exit(1)
    

def get_throughput_from_log(log_file_path: str):
    with open(log_file_path, 'r') as f:
        line = next((l for l in f if 'throughput' in l), None)
        if line is None:
            raise ValueError("No line containing 'throughput' found in the log file")
            sys.exit(1)
        
        match = re.search(r'(\d+\.\d+)', line)
        if match is None:
            raise ValueError("No number found in throughput line")
        
        value = round(float(match.group(1)))
        return value


def run_benchmark(config: Config):

    config.validate()

    isStandalone = (config.config_local != "" and config.config_remote == "")
    isNGT = config.environment in ["NGT", "NGT-MPI"]

    cmd = []

    if isStandalone:
        # Single machine, no MPI
        cmd += [
            "env EXPERIMENT_THREADS=" + str(config.ts[0]),
            "env EXPERIMENT_STREAMS=" + str(config.ts[1]),
            "" if config.cuda_visible_devices_local == "all" else "env CUDA_VISIBLE_DEVICES=" + config.cuda_visible_devices_local,
            "numactl --physcpubind=" + ",".join(map(str, config.cpus_local)),
            "cmsRun " + config.config_local
        ]

    elif config.mpi_impl == "OpenMPI":

        cmd += [
            "env LD_PRELOAD=/usr/lib64/libnvidia-ml.so.1" if isNGT else "",
            "mpirun" if isNGT else "cmsenv_mpirun",
            "" if isNGT else "--mca oob_tcp_if_exclude enp4s0f4u1u2c2",
            *(["--mca pml ob1 --mca btl vader,self,tcp"] if config.is_same_machine else [
                "--mca pml ucx",
                "-x UCX_TLS=" + config.ucx_tls,
                "-x UCX_PROTO_INFO=y", # to se e.g. which TLS are used
                "-x UCX_USE_MT_MUTEX=y",
                "-x UCX_RNDV_SCHEME=put_ppln"
            ]),
            "--hostfile /etc/mpi/hostfile" if isNGT else "",
            "--prtemca plm_ssh_agent " + os.path.join(os.path.dirname(os.path.abspath(__file__)), "env_ompi_kubexec.sh") if isNGT else "",
            f"-x EXPERIMENT_THREADS={config.ts[0]}",
            f"-x EXPERIMENT_STREAMS={config.ts[1]}",
            "--map-by node",
            "-np 1",
            "" if isNGT else "--host " + config.host_local,
            "" if config.cuda_visible_devices_local == "all" else "-x CUDA_VISIBLE_DEVICES=" + config.cuda_visible_devices_local,
            "" if config.ucx_net_devices_local == "" else "-x UCX_NET_DEVICES=" + config.ucx_net_devices_local,
            "--bind-to none numactl --physcpubind=" + ",".join(map(str, config.cpus_local)),
            "cmsRun " + config.config_local,
            ":",
            "-np 1",
            "" if isNGT else "--host " + config.host_remote,
            "" if config.cuda_visible_devices_remote == "all" else "-x CUDA_VISIBLE_DEVICES=" + config.cuda_visible_devices_remote,
            "" if config.ucx_net_devices_remote == "" else "-x UCX_NET_DEVICES=" + config.ucx_net_devices_remote,
            "--bind-to none numactl --physcpubind=" + ",".join(map(str, config.cpus_remote)),
            "cmsRun " + config.config_remote
        ]
    elif config.mpi_impl == "MPICH":
        cmd = [
            "env LD_PRELOAD=/usr/lib64/libnvidia-ml.so.1" if isNGT else "",
            "mpirun" if isNGT else "cmsenv_mpirun",
            "--launcher-exec " + os.path.abspath("env_mpich_kubexec.sh") if isNGT else "",
            "-genv UCX_TLS=" + config.ucx_tls,
            "-genv UCX_LOG_LEVEL=info", # to se e.g. which TLS are used
            "-genv UCX_RNDV_THRESH=inf",
            "" if isNGT else "-hosts " + config.host_local + "," + config.host_remote,
            "--bind-to none",
            f"-genv EXPERIMENT_THREADS {config.ts[0]}",
            f"-genv EXPERIMENT_STREAMS {config.ts[1]}",
            "" if config.is_same_machine else "-ppn 1", # one process per node (needed in case each node has multiple sockets)
            "-np 1",
            "" if config.cuda_visible_devices_local == "all" else "-env CUDA_VISIBLE_DEVICES=" + config.cuda_visible_devices_local,
            "" if config.ucx_net_devices_local == "" else "-env UCX_NET_DEVICES "+ config.ucx_net_devices_local,
            "numactl --physcpubind=" + ",".join(map(str, config.cpus_local)),
            "cmsRun " + config.config_local,
            ":",
            "-np 1",
            "" if config.cuda_visible_devices_remote == "all" else "-env CUDA_VISIBLE_DEVICES=" + config.cuda_visible_devices_remote,
            "" if config.ucx_net_devices_remote == "" else "-env UCX_NET_DEVICES "+ config.ucx_net_devices_remote,
            "numactl --physcpubind=" + ",".join(map(str, config.cpus_remote)),
            "cmsRun " + config.config_remote
        ]
    else:
        print("here be dragons")
        sys.exit(1)
        


    tmp_log_file = os.path.join(config.log_dir, "tmp.log")

    print("Run %d. [t,s] = [%d,%d]" % (config.runID, config.ts[0], config.ts[1]))
    print("Command:")
    print(" ".join(cmd))
    if not config.print_cmd_no_run:
        log_file_path = os.path.join(config.log_dir,
                                     f"{config.mpi_impl}_{config.label}_t{config.ts[0]}_s{config.ts[1]}_r{config.runID}.log")
        print("Logging to:", tmp_log_file)
        print("Final log will be saved to:", log_file_path)
        with open(tmp_log_file, "w") as log_file:
            log_file.write("Command:\n")
            log_file.write(" ".join(cmd) + "\n")
            log_file.write("-"*80 + "\n")
            log_file.flush()

            # run and get output
            process = subprocess.Popen(" ".join(cmd), shell=True, stdout=log_file, stderr=subprocess.STDOUT)
            r = process.wait()
            if process.returncode != 0:
                print("Command failed with return code", r)
                sys.exit(1)

        throughput_this_run = get_throughput_from_log(tmp_log_file)
        # append throughput to log filename and rename

        os.rename(tmp_log_file, log_file_path)
        print("Final log saved.")
        print("Throughput this run:", throughput_this_run, "events/s")
        print()


def main():


    # Comment / uncomment tests depending on what/where to run
    # Individual test-related config (hosts, t_s pairs, config paths, etc.) is set below
    # Config unrelated to specific tests is set (when needed) above, in run_benchmark()
    
    # Before running tests, enable "print_cmd_no_run" to check that the commands are correct!


    GlobalConfig.mpi_impl = "OpenMPI"
    GlobalConfig.print_cmd_no_run = False
    GlobalConfig.run_first_ts_pair_only = False
    GlobalConfig.log_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")


    firstRunID = 0
    lastRunID = 4
    for i_run in range(firstRunID, lastRunID): # [first,last)

        GlobalConfig.runID = i_run

        if RUN_MILAN_STANDALONE_CPUONLY == True:
            # Milan standalone (CPU only)
            # ------------------------------------------------------------
            config = Config()
            config.environment = "HLT"
            config.host_local = "gputest-milan-02"
            config.config_local = "hlt_test.py"
            config.label = "milan_standalone_cpuonly"
            config.cuda_visible_devices_local = ""

            ts_pairs = [[32, 24], [24, 18], [16, 12], [8, 6]]

            for ts in ts_pairs:
                config.ts = ts
                config.cpus_local = range(32, 32 + ts[0])
                print("cpus_local:", config.cpus_local)

                run_benchmark(config)
                if config.run_first_ts_pair_only: break

        if RUN_MILAN_STANDALONE == True:
            # Milan standalone
            # ------------------------------------------------------------
            config = Config()
            config.environment = "HLT"
            config.host_local = "gputest-milan-02"
            config.config_local = "hlt_test.py"
            config.label = "milan_standalone"

            ts_pairs = [[32, 24], [24, 18], [16, 12], [8, 6]]

            for ts in ts_pairs:
                config.ts = ts
                config.cpus_local = range(32, 32 + ts[0])
                print("cpus_local:", config.cpus_local)

                run_benchmark(config)
                if config.run_first_ts_pair_only: break


        if RUN_MILAN_MILAN_CPUONLY == True:
            # Milan-Milan (CPU only)
            # ------------------------------------------------------------
            config = Config()
            config.environment = "HLT"
            config.host_local = "gputest-milan-02"
            config.host_remote = "gputest-milan-02"
            config.is_same_machine = True
            config.cuda_visible_devices_local = ""
            config.cuda_visible_devices_remote = ""
            config.config_local = "hlt_local.py"
            config.config_remote = "hlt_remote.py"
            config.label = "milan_milan_2sockets_cpuonly"

            ts_pairs = [[32, 24], [24, 18], [16, 12], [8, 6]]

            for ts in ts_pairs:
                config.ts = ts
                config.cpus_local = range(0, 0 + ts[0])
                config.cpus_remote = range(32, 32 + ts[0])

                run_benchmark(config)
                if config.run_first_ts_pair_only: break

        if RUN_MILAN_MILAN == True:
            # Milan-Milan
            # ------------------------------------------------------------
            config = Config()
            config.environment = "HLT"
            config.host_local = "gputest-milan-02"
            config.host_remote = "gputest-milan-02"
            config.is_same_machine = True
            config.config_local = "hlt_local.py"
            config.config_remote = "hlt_remote.py"
            config.label = "milan_milan_2sockets"

            ts_pairs = [[32, 24], [24, 18], [16, 12], [8, 6]]

            for ts in ts_pairs:
                config.ts = ts
                config.cpus_local = range(0, 0 + ts[0])
                config.cpus_remote = range(32, 32 + ts[0])

                run_benchmark(config)
                if config.run_first_ts_pair_only: break


        if RUN_MILAN_GENOA_CPUONLY == True:
            # Milan-Genoa (cpu only)
            # ------------------------------------------------------------
            config = Config()
            config.environment = "HLT"
            config.host_local = "gputest-milan-02"
            config.host_remote = "gputest-genoa-02"
            config.ucx_net_devices_local = "mlx5_2:1"
            config.ucx_net_devices_remote = "mlx5_0:1"
            config.cuda_visible_devices_local = ""
            config.cuda_visible_devices_remote = ""
            config.ucx_tls = "rc_mlx5,rc_x,ud_x,sm,self,cuda_copy,cuda_ipc,gdr_copy"
            config.config_local = "hlt_local.py"
            config.config_remote = "hlt_remote.py"
            config.label = "milan_genoa_ib100G_cpuonly"

            ts_pairs = [[32, 24], [24, 18], [16, 12], [8, 6]]
            
            for ts in ts_pairs:
                config.ts = ts
                config.cpus_local = range(32, 32 + ts[0])
                config.cpus_remote = range(48, 48 + ts[0])
                
                run_benchmark(config)
                if config.run_first_ts_pair_only: break

     
        if RUN_MILAN_GENOA == True:
            # Milan-Genoa
            # ------------------------------------------------------------
            config = Config()
            config.environment = "HLT"
            config.host_local = "gputest-milan-02"
            config.host_remote = "gputest-genoa-02"
            config.ucx_net_devices_local = "mlx5_2:1"
            config.ucx_net_devices_remote = "mlx5_0:1"
            config.ucx_tls = "rc_mlx5,rc_x,ud_x,sm,self,cuda_copy,cuda_ipc,gdr_copy"
            config.config_local = "hlt_local.py"
            config.config_remote = "hlt_remote.py"
            config.label = "milan_genoa_ib100G"

            ts_pairs = [[32, 24], [24, 18], [16, 12], [8, 6]]
            
            for ts in ts_pairs:
                config.ts = ts
                config.cpus_local = range(32, 32 + ts[0])
                config.cpus_remote = range(48, 48 + ts[0])
                
                run_benchmark(config)
                if config.run_first_ts_pair_only: break
        

        if RUN_NGT_STANDALONE == True:
            # NGT standalone
            # ------------------------------------------------------------
            config = Config()
            config.environment = "NGT"
            config.config_local = os.path.join(os.path.dirname(os.path.abspath(__file__)), "configs/hlt_test.py")
            config.label = "ngt_standalone"
            config.cuda_visible_devices_local = "2"


            ts_pairs = [[32, 24], [24, 18], [16, 12], [8, 6]]
            for ts in ts_pairs:
                config.ts = ts
                config.cpus_local = range(32, 32 + ts[0])

                run_benchmark(config)
                if config.run_first_ts_pair_only: break
        
        if RUN_NGT_STANDALONE_CPUONLY == True:
            # NGT standalone (CPU only)
            # ------------------------------------------------------------
            config = Config()
            config.environment = "NGT"
            config.config_local = os.path.join(os.path.dirname(os.path.abspath(__file__)), "configs/hlt_test.py")
            config.label = "ngt_standalone_cpuonly"
            config.cuda_visible_devices_local = ""
            ts_pairs = [[32, 24], [24, 18], [16, 12], [8, 6]]
            for ts in ts_pairs:
                config.ts = ts
                config.cpus_local = range(32, 32 + ts[0])

                run_benchmark(config)
                if config.run_first_ts_pair_only: break

        if RUN_NGT_NGT_XSOCKET == True:
            # NGT-NGT (single machine)
            # ------------------------------------------------------------
            config = Config()
            config.environment = "NGT"
            config.config_local = os.path.join(os.path.dirname(os.path.abspath(__file__)), "configs/hlt_local.py")
            config.config_remote = os.path.join(os.path.dirname(os.path.abspath(__file__)), "configs/hlt_remote.py")
            config.is_same_machine = True
            config.cuda_visible_devices_local = ""
            config.cuda_visible_devices_remote = "2"
            config.label = "ngt_ngt_2sockets"

            ts_pairs = [[29, 24], [24, 18], [16, 12], [8, 6]]
            for ts in ts_pairs:
                config.ts = ts
                config.cpus_local = range(1, 1 + ts[0])
                config.cpus_remote = range(32, 32 + ts[0])

                run_benchmark(config)
                if config.run_first_ts_pair_only: break


        if RUN_NGT_NGT_XSOCKET_CPUONLY == True:
            # NGT-NGT (single machine, CPU only)
            # ------------------------------------------------------------
            config = Config()
            config.environment = "NGT"
            config.config_local = os.path.join(os.path.dirname(os.path.abspath(__file__)), "configs/hlt_local.py")
            config.config_remote = os.path.join(os.path.dirname(os.path.abspath(__file__)), "configs/hlt_remote.py")
            config.is_same_machine = True
            config.cuda_visible_devices_local = ""
            config.cuda_visible_devices_remote = ""
            config.label = "ngt_ngt_2sockets_cpuonly"

            ts_pairs = [[29, 24], [24, 18], [16, 12], [8, 6]]
            for ts in ts_pairs:
                config.ts = ts
                config.cpus_local = range(1, 1 + ts[0])
                config.cpus_remote = range(32, 32 + ts[0])

                run_benchmark(config)
                if config.run_first_ts_pair_only: break


        if RUN_NGT_NGT_CPUONLY == True:
            # NGT-NGT (two machines, CPU only)
            # ------------------------------------------------------------
            config = Config()
            config.environment = "NGT-MPI"
            config.ucx_net_devices_local = "mlx5_2:1"
            config.ucx_net_devices_remote = "mlx5_2:1"
            config.cuda_visible_devices_local = ""
            config.cuda_visible_devices_remote = ""
            config.config_local = os.path.join(os.path.dirname(os.path.abspath(__file__)), "configs/hlt_local.py")
            config.config_remote = os.path.join(os.path.dirname(os.path.abspath(__file__)), "configs/hlt_remote.py")
            config.ucx_tls = "rc_mlx5,rc_x,ud_x,sm,self,cuda_copy,cuda_ipc,gdr_copy"
            config.label = "ngt_ngt_ib400G_cpuonly"

            ts_pairs = [[32, 24], [24, 18], [16, 12], [8, 6]]
            for ts in ts_pairs:
                config.ts = ts
                config.cpus_local = range(32, 32 + ts[0])
                config.cpus_remote = range(32, 32 + ts[0])

                run_benchmark(config)
                if config.run_first_ts_pair_only: break

        if RUN_NGT_NGT == True:
            # NGT-NGT (two machines)
            # ------------------------------------------------------------
            config = Config()
            config.environment = "NGT-MPI"
            config.ucx_net_devices_local = "mlx5_2:1"
            config.ucx_net_devices_remote = "mlx5_2:1"
            config.cuda_visible_devices_local = "2"
            config.cuda_visible_devices_remote = "2"
            config.config_local = os.path.join(os.path.dirname(os.path.abspath(__file__)), "configs/hlt_local.py")
            config.config_remote = os.path.join(os.path.dirname(os.path.abspath(__file__)), "configs/hlt_remote.py")
            config.ucx_tls = "rc_mlx5,rc_x,ud_x,sm,self,cuda_copy,cuda_ipc,gdr_copy"
            config.label = "ngt_ngt_ib400G"

            ts_pairs = [[32, 24], [24, 18], [16, 12], [8, 6]]
            for ts in ts_pairs:
                config.ts = ts
                config.cpus_local = range(32, 32 + ts[0])
                config.cpus_remote = range(32, 32 + ts[0])

                run_benchmark(config)
                if config.run_first_ts_pair_only: break



if __name__ == "__main__":
    main()
