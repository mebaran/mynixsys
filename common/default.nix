{pkgs, ...}:
{
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nixpkgs.config.allowUnfree = true;

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
  };
  environment.systemPackages = [
    pkgs.wl-clipboard
    pkgs.neovim
    pkgs.home-manager
  ];

  users.defaultUserShell = pkgs.zsh;
}
