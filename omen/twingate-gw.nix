# Twingate in its own network namespace, so it never fights the host's
# tailscale over routes or DNS. Postgres (or anything TCP) behind the VPN is
# reached through per-IP forwards in 10.89.0.0/24.
#
# The forwards are not in this repo: they come from ~/.pg_service.conf.
# Any section with a `hostaddr` in 10.89.0.0/24 gets a forward from that
# address to its `host` (and `port`, default 5432):
#
#   [some-db]
#   host=db.internal.example.com
#   hostaddr=10.89.0.10
#
# libpq connects to hostaddr but still uses host for TLS and .pgpass.
#
# Flow: a user path unit notices edits to ~/.pg_service.conf and writes just
# the "hostaddr host port" triples to /run/twingate-gw/forwards; the container
# sees that file change and restarts its forwards.
#
# Log in (first-time setup, or when the session expires): `twingate-gw-login`.
{
  lib,
  pkgs,
  ...
}: let
  name = "twingate-gw";
  hostIface = "ve-${name}";
  subnet = "10.89.0";
  hostAddress = "${subnet}.1";
  localAddress = "${subnet}.2";
  forwardsDir = "/run/${name}";
  forwardsFile = "${forwardsDir}/forwards";

  # ~/.pg_service.conf -> "hostaddr host port" lines (no passwords)
  sync = pkgs.writeShellApplication {
    name = "${name}-sync";
    runtimeInputs = [pkgs.gawk pkgs.coreutils];
    text = ''
      src="$HOME/.pg_service.conf"
      tmp="$(mktemp ${forwardsDir}/.forwards.XXXXXX)"
      if [ -r "$src" ]; then
        awk '
          function flush() {
            if (addr ~ /^${lib.escape ["."] subnet}\.[0-9]+$/ && addr != "${hostAddress}" && addr != "${localAddress}" \
                && host ~ /^[A-Za-z0-9.-]+$/ && port ~ /^[0-9]+$/)
              print addr, host, port
            addr = ""; host = ""; port = "5432"
          }
          BEGIN { port = "5432" }
          /^[[:space:]]*\[/ { flush(); next }
          /^[[:space:]]*(#|$)/ { next }
          {
            key = $0; sub(/[[:space:]]*=.*/, "", key); gsub(/[[:space:]]/, "", key)
            val = $0; sub(/^[^=]*=[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
            if (key == "hostaddr") addr = val
            else if (key == "host") host = val
            else if (key == "port") port = val
          }
          END { flush() }
        ' "$src" > "$tmp"
      fi
      chmod 0644 "$tmp"
      mv -f "$tmp" ${forwardsFile}
    '';
  };

  # Set up / reconnect twingate in the container and wait until it's online.
  login = pkgs.writeShellApplication {
    name = "${name}-login";
    runtimeInputs = [pkgs.coreutils pkgs.gnugrep];
    text = ''
      if [ "$(id -u)" != 0 ]; then
        exec sudo "$0" "$@"
      fi
      run() { nixos-container run ${name} -- "$@"; }
      status() { run twingate status 2>/dev/null || true; }

      if [ "$(status)" = online ] && [ "''${1:-}" != --setup ]; then
        echo "${name}: already online"
        exit 0
      fi

      # No network configured yet (or asked to redo it): interactive setup.
      # The packaged network.conf is just a newline, so look for a real name.
      if [ "''${1:-}" = --setup ] || ! grep -qs '[^[:space:]]' /var/lib/nixos-containers/${name}/etc/twingate/network.conf; then
        run twingate setup
      else
        run twingate start
      fi

      shown_url=""
      last=""
      for _ in $(seq 1 180); do
        st="$(status)"
        if [ "$st" != "$last" ]; then
          echo "${name}: $st"
          last="$st"
        fi
        [ "$st" = online ] && exit 0
        url="$(run journalctl -u twingate --no-pager -n 100 -o cat 2>/dev/null \
          | grep -o 'https://[^[:space:]"]*twingate[^[:space:]"]*' | tail -n 1 || true)"
        if [ -n "$url" ] && [ "$url" != "$shown_url" ]; then
          echo "Authenticate in your browser: $url"
          shown_url="$url"
        fi
        sleep 1
      done
      echo "${name}: not online after 3 minutes (last status: $last)" >&2
      exit 1
    '';
  };
in {
  mynixsys.unfreePackages = ["twingate"];

  environment.systemPackages = [login];

  systemd.tmpfiles.rules = ["d ${forwardsDir} 0755 mebaran users -"];

  # Runs under mebaran's (lingering) user manager.
  systemd.user.services."${name}-sync" = {
    description = "Write ${name} forwards from ~/.pg_service.conf";
    wantedBy = ["default.target"];
    unitConfig.ConditionUser = "mebaran";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe sync;
    };
  };
  systemd.user.paths."${name}-sync" = {
    description = "Watch ~/.pg_service.conf for ${name} forwards";
    wantedBy = ["default.target"];
    unitConfig.ConditionUser = "mebaran";
    pathConfig.PathChanged = "%h/.pg_service.conf";
  };

  containers.${name} = {
    autoStart = true;
    privateNetwork = true;
    inherit hostAddress localAddress;

    allowedDevices = [
      {
        node = "/dev/net/tun";
        modifier = "rwm";
      }
    ];
    bindMounts = {
      "/dev/net/tun".hostPath = "/dev/net/tun";
      ${forwardsDir} = {
        hostPath = forwardsDir;
        isReadOnly = true;
      };
    };

    config = {
      lib,
      pkgs,
      ...
    }: {
      imports = [
        ../common/unfree.nix
        ../common/twingate.nix
      ];

      # twingate drives the container's own resolved; don't copy the host's.
      networking.useHostResolvConf = lib.mkForce false;
      networking.nameservers = ["1.1.1.1" "9.9.9.9"];
      # Only omen can reach eth0, and forwards may use any port.
      networking.firewall.trustedInterfaces = ["eth0"];

      # One socat per forward, each listening on its own address. Restarted
      # (and the address set rebuilt) whenever the forwards file changes.
      systemd.services.pg-forwards = {
        description = "TCP forwards through twingate";
        wantedBy = ["multi-user.target"];
        after = ["twingate.service"];
        path = [pkgs.iproute2 pkgs.socat pkgs.gawk pkgs.coreutils];
        serviceConfig.Restart = "always";
        serviceConfig.RestartSec = "2s";
        script = ''
          # Drop forward addresses from a previous run, keeping the container's own.
          ip -4 -o addr show dev eth0 | awk '{print $4}' | while read -r cidr; do
            case "$cidr" in
              ${localAddress}/*) ;;
              ${subnet}.*) ip addr del "$cidr" dev eth0 ;;
            esac
          done

          started=0
          if [ -r ${forwardsFile} ]; then
            while read -r addr host port; do
              [ -n "$addr" ] || continue
              ip addr add "$addr/32" dev eth0
              socat "TCP-LISTEN:$port,bind=$addr,fork,reuseaddr" "TCP:$host:$port" &
              started=1
            done < ${forwardsFile}
          fi

          if [ "$started" = 1 ]; then
            # If any forward dies, exit so systemd restarts the whole set.
            wait -n
            exit 1
          fi
          exec sleep infinity
        '';
      };
      systemd.services.pg-forwards-reload = {
        description = "Restart pg-forwards after the forwards file changes";
        serviceConfig.Type = "oneshot";
        script = "${pkgs.systemd}/bin/systemctl restart pg-forwards.service";
      };
      systemd.paths.pg-forwards-reload = {
        wantedBy = ["multi-user.target"];
        pathConfig.PathChanged = forwardsFile;
      };

      system.stateVersion = "26.11";
    };
  };

  # The container only gets a route for its own address; send the rest of the
  # subnet (the forward addresses) its way too.
  systemd.services."container@${name}".postStart = lib.mkAfter ''
    ip route replace ${subnet}.0/24 dev ${hostIface}
  '';

  networking.nat = {
    enable = true;
    internalInterfaces = [hostIface];
  };
}
