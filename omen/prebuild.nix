# Pre-build this host's system from the pushed flake so `nh os switch .`
# finds everything already in the store. Builds only; never switches.
{
  config,
  pkgs,
  ...
}: let
  host = config.networking.hostName;
  flake = "github:mebaran/mynixsys";
  # Direct root (not an auto/result link), so `nh clean` leaves it alone.
  gcroot = "/nix/var/nix/gcroots/${host}-prebuild";
in {
  systemd.services."${host}-prebuild" = {
    description = "Pre-build ${host} system from ${flake}";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    path = [config.nix.package pkgs.git];
    serviceConfig = {
      Type = "oneshot";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    script = ''
      out=$(nix build --refresh --no-link --print-out-paths \
        "${flake}#nixosConfigurations.${host}.config.system.build.toplevel")
      ln -sfn "$out" ${gcroot}
      echo "prebuilt $out"
    '';
  };

  systemd.timers."${host}-prebuild" = {
    wantedBy = ["timers.target"];
    timerConfig = {
      # Monday's lock-update CI lands ~09:00 UTC; daily also covers ad-hoc pushes.
      OnCalendar = "*-*-* 04:00:00";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };
}
