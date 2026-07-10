{pkgs, ...}: {
  mynixsys.unfreePackages = [
    "cuda-merged"
    "cuda_cccl"
    "cuda_cuobjdump"
    "cuda_cudart"
    "cuda_cupti"
    "cuda_cuxxfilt"
    "cuda_gdb"
    "cuda_nvcc"
    "cuda_nvdisasm"
    "cuda_nvml_dev"
    "cuda_nvprune"
    "cuda_nvrtc"
    "cuda_nvtx"
    "cuda_profiler_api"
    "cuda_sanitizer_api"
    "libcublas"
    "libcufft"
    "libcurand"
    "libcusolver"
    "libcusparse"
    "libnpp"
    "libnvjitlink"
    "nvidia-settings"
    "nvidia-x11"
    "steam-unwrapped"
  ];

  #cuda
  hardware = {
    nvidia-container-toolkit.enable = true;
    nvidia.open = true;
    graphics.enable = true;
  };
  services.xserver.videoDrivers = ["nvidia"];
  environment.sessionVariables = {
    CUDA_PATH = "${pkgs.cudatoolkit}";
    EXTRA_LDFLAGS = "-L/lib -L${pkgs.linuxPackages.nvidia_x11}/lib";
    EXTRA_CCFLAGS = "-I/usr/include";
    LD_LIBRARY_PATH = [
      "/usr/lib/wsl/lib"
      "${pkgs.libGL}/lib"
      "${pkgs.linuxPackages.nvidia_x11}/lib"
      "${pkgs.ncurses5}/lib"
    ];
    MESA_D3D12_DEFAULT_ADAPTER_NAME = "Nvidia";
  };
  environment.systemPackages = [
    pkgs.steam-run
  ];
  # services.ollama = {
  #   enable = true;
  #   package = pkgs.ollama-cuda;
  #   openFirewall = true;
  # };
}
