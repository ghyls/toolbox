#include <algorithm>
#include <cstring>
#include <iostream>
#include <mpi.h>
#include <vector>

// Define USE_CUDA or USE_ROCM at compile time via -DUSE_CUDA or -DUSE_ROCM

#ifdef USE_CUDA
#include <cuda_runtime.h>
#define gpuMalloc cudaMalloc
#define gpuFree cudaFree
#define gpuFreeHost cudaFreeHost
#define gpuSuccess cudaSuccess
#elif defined(USE_ROCM)
#define __HIP_PLATFORM_AMD__
#include <hip/hip_runtime.h>
#define gpuMalloc hipMalloc
#define gpuFree hipFree
#define gpuFreeHost hipHostFree
#define gpuSuccess hipSuccess
#else
#error "Please define either USE_CUDA or USE_ROCM"
#endif

int main(int argc, char *argv[]) {
  MPI_Init(&argc, &argv);

  int rank, size;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  MPI_Comm_size(MPI_COMM_WORLD, &size);

  if (size != 2) {
    if (rank == 0)
      std::cerr << "Error: This program requires exactly 2 MPI processes\n";
    MPI_Finalize();
    return 1;
  }

  if (argc != 2) {
    if (rank == 0)
      std::cerr << "Error: Missing argument. Use HtoH, HtoD, DtoH, or DtoD\n";
    MPI_Finalize();
    return 1;
  }

  std::string mode = argv[1];
  if (mode != "HtoH" && mode != "HtoD" && mode != "DtoH" && mode != "DtoD") {
    if (rank == 0)
      std::cerr << "Error: Invalid argument. Use HtoH, HtoD, DtoH, or DtoD\n";
    MPI_Finalize();
    return 1;
  }

  // Configuration parameters
  const size_t buffer_size = 1024 * 1024 * 100; // Maximum buffer size (1 GB)
  const size_t min_size = 1;                    // Minimum message size (bytes)
  const size_t max_size_linear = 2;             // End of linear range (bytes)
  const size_t geometric_start = 2;      // Start of geometric range (bytes)
  const size_t geometric_multiplier = 2; // Multiplier for geometric progression
  const int n_warmup_iterations = 5;     // Number of warmup iterations
  const int n_measurement_iterations = 5; // Number of measurement iterations

  void *send_buffer = nullptr;
  void *recv_buffer = nullptr;

  bool send_on_device = (rank == 0 && (mode == "DtoH" || mode == "DtoD"));
  bool recv_on_device = (rank == 1 && (mode == "HtoD" || mode == "DtoD"));

  if (rank == 0) {
    if (send_on_device) {
      if (gpuMalloc(&send_buffer, buffer_size) != gpuSuccess) {
        std::cerr << "Error: gpuMalloc failed for send buffer\n";
        MPI_Finalize();
        return 1;
      }
    } else {
      send_buffer = malloc(buffer_size); // Use standard malloc for host memory
    }
  } else {
    if (recv_on_device) {
      if (gpuMalloc(&recv_buffer, buffer_size) != gpuSuccess) {
        std::cerr << "Error: gpuMalloc failed for recv buffer\n";
        MPI_Finalize();
        return 1;
      }
    } else {
      recv_buffer = malloc(buffer_size); // Use standard malloc for host memory
    }
  }

  std::vector<size_t> sizes;

  for (size_t s = min_size; s <= max_size_linear; s++) {
    sizes.push_back(s);
  }
  for (size_t s = geometric_start; s <= buffer_size;
       s *= geometric_multiplier) {
    sizes.push_back(s);
  }

  std::sort(sizes.begin(), sizes.end());
  sizes.erase(std::unique(sizes.begin(), sizes.end()), sizes.end());

  if (rank == 0) {
    std::cout << "# " << mode << "\n";
    std::cout << "# bytes time_us bw_Gbps\n";
  }

  for (size_t msg_size : sizes) {
    MPI_Barrier(MPI_COMM_WORLD);

    for (int i = 0; i < n_warmup_iterations; i++) {
      if (rank == 0) {
        MPI_Send(send_buffer, msg_size, MPI_BYTE, 1, 0, MPI_COMM_WORLD);
      } else {
        MPI_Recv(recv_buffer, msg_size, MPI_BYTE, 0, 0, MPI_COMM_WORLD,
                 MPI_STATUS_IGNORE);
      }
    }

    MPI_Barrier(MPI_COMM_WORLD);
    double start_time = MPI_Wtime();

    for (int i = 0; i < n_measurement_iterations; i++) {
      if (rank == 0) {
        MPI_Send(send_buffer, msg_size, MPI_BYTE, 1, 0, MPI_COMM_WORLD);
      } else {
        MPI_Recv(recv_buffer, msg_size, MPI_BYTE, 0, 0, MPI_COMM_WORLD,
                 MPI_STATUS_IGNORE);
      }
    }

    MPI_Barrier(MPI_COMM_WORLD);
    double end_time = MPI_Wtime();

    if (rank == 0) {
      double time_per_msg =
          (end_time - start_time) / n_measurement_iterations * 1e6;
      size_t bytes = msg_size;
      double bw_gbps = (bytes * 8 / 1e9) / (time_per_msg / 1e6);
      std::cout << bytes << " " << time_per_msg << " " << bw_gbps << "\n";
    }
  }

  if (rank == 0) {
    if (send_on_device) {
      gpuFree(send_buffer);
    } else {
      gpuFreeHost(send_buffer);
    }
  } else {
    if (recv_on_device) {
      gpuFree(recv_buffer);
    } else {
      gpuFreeHost(recv_buffer);
    }
  }

  MPI_Finalize();
  return 0;
}
