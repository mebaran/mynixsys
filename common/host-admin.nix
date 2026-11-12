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
        run0 /run/current-system/bin/switch-to-configuration boot
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

  # Elevate via run0 (polkit) instead of nh's auto order (doas, sudo, run0, ...).
  # polkit shows the desktop agent's dialog when there's no TTY (e.g. agents
  # like Claude Code running `nh os switch`) and a text prompt over ssh.
  environment.sessionVariables.NH_ELEVATION_STRATEGY = "/run/current-system/sw/bin/run0";

  environment.systemPackages = [
    pkgs.home-manager
    nixos-clean
  ];
}
