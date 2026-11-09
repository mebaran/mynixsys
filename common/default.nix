{pkgs, ...}: {
  imports = [
    ./unfree.nix
  ];

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    # System-wide caches: used by every user, trusted or not.
    substituters = [
      "https://cache.numtide.com"
      "https://noctalia.cachix.org"
    ];
    trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  # Enable common container config files in /etc/containers
  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;

      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = true;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  #userspace
  programs = {
    git.enable = true;
    nix-ld.enable = true;
    zsh.enable = true;
    neovim.enable = true;
  };

  # Terminfo for the terminals we ssh in from (xterm-ghostty and friends),
  # so TERM is recognized and key handling works.
  environment.enableAllTerminfo = true;

  environment.systemPackages = [
    pkgs.wl-clipboard
    pkgs.gnumake
    pkgs.gcc
    pkgs.cmake
    pkgs.pkg-config
  ];

  users.defaultUserShell = pkgs.zsh;
}
