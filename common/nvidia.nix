{pkgs, ...}: 
{
  nixpkgs.config.allowUnfree = true;

  #cuda
  hardware = {
    nvidia-container-toolkit.enable = true;
    nvidia = {
      open = true;
      nvidiaSettings = false;
    };
    graphics.enable = true;
  };
  services.xserver.videoDrivers = ["nvidia"];
  environment.sessionVariables = {
    CUDA_PATH = "${pkgs.cudatoolkit}";
    EXTRA_LDFLAGS = "-L/lib -L${pkgs.linuxPackages.nvidia_x11}/lib";
    EXTRA_CCFLAGS = "-I/usr/include";
    LD_LIBRARY_PATH = [
      "/usr/lib/wsl/lib"
      "${pkgs.linuxPackages.nvidia_x11}/lib"
      "${pkgs.ncurses5}/lib"
    ];
    MESA_D3D12_DEFAULT_ADAPTER_NAME = "Nvidia";
  };
}

