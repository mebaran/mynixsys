{

  # Abstracted WSL-specific configuration
  # This is based on the original configuration.nix but without imports
  # to make it reusable in flakes.
  networking.hostName = "nixos-wsl";

  wsl.enable = true;
  wsl.defaultUser = "mebaran";
  wsl.interop.includePath = false;
  wsl.interop.register = true;
  wsl.useWindowsDriver = true;

  # System state version (keep this as-is for compatibility)
  system.stateVersion = "24.11";
}
