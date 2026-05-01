{ lib, pkgs, ... }:

let
  hostAuthorizedKeysDir = "/var/lib/hermes-agent/authorized_keys.d";
  guestAuthorizedKeysDir = "/run/host-authorized-keys";
in
{
  system.stateVersion = "25.05";

  networking.hostName = "hermes-vm";
  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.useNetworkd = true;

  systemd.network.enable = true;
  systemd.network.networks."20-uplink" = {
    matchConfig.Name = "eth0";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = lib.mkDefault true;
    };
    linkConfig.RequiredForOnline = "routable";
  };

  services.getty.autologinUser = "root";
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "yes";
    };
  };

  environment.systemPackages = with pkgs; [
    curl
    duckdb
    bun
    gh
    git
    htop
    jq
    uv
    vim
  ];

  microvm = {
    hypervisor = lib.mkDefault "cloud-hypervisor";
    vsock.cid = 43;
    vcpu = 4;
    mem = 4096;
    shares = [
      {
        proto = "virtiofs";
        tag = "host-authorized-keys";
        source = hostAuthorizedKeysDir;
        mountPoint = guestAuthorizedKeysDir;
      }
    ];
    interfaces = [
      {
        type = "tap";
        id = "vm-hermes";
        mac = "02:00:00:01:01:01";
      }
    ];
    volumes = [
      {
        image = "var.img";
        mountPoint = "/var";
        size = 16384;
      }
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/hermes 0750 hermes hermes - -"
    "d /var/lib/hermes/workspace 0750 hermes hermes - -"
    "f /var/lib/hermes/hermes.env 0600 hermes hermes - -"
    "d /root/.ssh 0700 root root - -"
  ];

  systemd.services.install-host-authorized-keys = {
    description = "Install SSH authorized keys from the host share";
    wantedBy = [ "multi-user.target" ];
    before = [ "sshd.service" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu

      install -d -m 0700 /root/.ssh
      tmp="$(mktemp)"
      trap 'rm -f "$tmp"' EXIT

      if [ -d ${lib.escapeShellArg guestAuthorizedKeysDir} ]; then
        find ${lib.escapeShellArg guestAuthorizedKeysDir} -maxdepth 1 -type f -name '*.pub' -print0 \
          | sort -z \
          | xargs -0r cat -- > "$tmp"
      else
        : > "$tmp"
      fi

      install -m 0600 "$tmp" /root/.ssh/authorized_keys
    '';
  };

  services.hermes-agent = {
    enable = true;
    environmentFiles = [ "/var/lib/hermes/hermes.env" ];
    settings = {
      terminal.backend = "local";
      toolsets = [ "all" ];
    };
    documents = {
      "SOUL.md" = ''
        You are Hermes running inside a dedicated MicroVM.
        Persist useful long-term context and operate from this isolated environment.
      '';
    };
  };
}
