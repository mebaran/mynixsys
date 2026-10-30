# Tools for managing a NixOS host from the inside.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Delete old NixOS system generations, GC the store, and rewrite
  # the bootloader entries so stale kernels/initrds are pruned from /boot.
  nixos-clean = pkgs.writeShellApplication {
    name = "nixos-clean";
    runtimeInputs = [pkgs.nh];
    text =
      ''
        nh clean profile /nix/var/nix/profiles/system --keep "''${1:-1}"
      ''
      + lib.optionalString config.boot.loader.systemd-boot.enable ''
        sudo /run/current-system/bin/switch-to-configuration boot
      '';
  };
in {
  # Weekly `nh clean all` across every profile (system, users, home-manager)
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep 3 --keep-since 7d";
    };
  };

  environment.systemPackages = [
    pkgs.home-manager
    nixos-clean
  ];
}
