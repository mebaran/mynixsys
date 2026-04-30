{
  config,
  lib,
  pkgs,
  llm-agents,
  ...
}: let
  vmName = "openclaw";
  bridgeName = "microvm_br0";
  tapName = "vm_openclaw0";
  hostAddress = "10.42.0.1";
  guestAddress = "10.42.0.2";
  gatewayPort = 18789;
  ollamaPort = 11434;
  sshRunDir = "/run/openclaw-microvm";
  sshDir = "${sshRunDir}/ssh";
  guestShareDir = "${sshRunDir}/guest";
  workspaceDir = "/home/openclaw/workspace";
  llmPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  openclawConfig = pkgs.replaceVars ./openclaw/openclaw.json {
    inherit workspaceDir;
    gatewayPort = toString gatewayPort;
  };
  refreshKnownHosts = pkgs.writeShellApplication {
    name = "refresh-openclaw-microvm-ssh-known-hosts";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssh
    ];
    text = ''
      tmp_known_hosts="$(mktemp)"
      trap 'rm -f "$tmp_known_hosts"' EXIT

      for _ in $(seq 1 30); do
        if ssh-keyscan -T 1 -t ed25519 ${guestAddress} >"$tmp_known_hosts" 2>/dev/null && [ -s "$tmp_known_hosts" ]; then
          install -D -m 0644 "$tmp_known_hosts" ${sshDir}/known_hosts
          exit 0
        fi

        sleep 1
      done

      echo "failed to refresh SSH host key for ${vmName} at ${guestAddress}" >&2
      exit 1
    '';
  };
  guestOpenClaw = pkgs.writeShellApplication {
    name = "openclaw";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      real_openclaw=${lib.getExe llmPkgs.openclaw}

      if [ "''${1:-}" = "tui" ]; then
        shift

        declare -a args=()
        needs_url=1
        needs_token=1

        for arg in "$@"; do
          case "$arg" in
            --url|--url=*)
              needs_url=0
              ;;
            --token|--token=*)
              needs_token=0
              ;;
          esac
        done

        if [ "$needs_url" -eq 1 ] && [ -n "''${OPENCLAW_GATEWAY_URL:-}" ]; then
          args+=(--url "$OPENCLAW_GATEWAY_URL")
        fi

        if [ "$needs_token" -eq 1 ] && [ -n "''${OPENCLAW_GATEWAY_TOKEN_FILE:-}" ] && [ -r "$OPENCLAW_GATEWAY_TOKEN_FILE" ]; then
          args+=(--token "$(cat "$OPENCLAW_GATEWAY_TOKEN_FILE")")
        fi

        exec "$real_openclaw" tui "''${args[@]}" "$@"
      fi

      exec "$real_openclaw" "$@"
    '';
  };
  hostOpenClaw = pkgs.writeShellApplication {
    name = "openclaw";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      real_openclaw=${lib.getExe llmPkgs.openclaw}
      connection_env=${sshRunDir}/connection.env

      if [ "''${1:-}" = "tui" ]; then
        shift

        declare -a args=()
        needs_url=1
        needs_token=1

        for arg in "$@"; do
          case "$arg" in
            --url|--url=*)
              needs_url=0
              ;;
            --token|--token=*)
              needs_token=0
              ;;
          esac
        done

        if [ -r "$connection_env" ]; then
          # shellcheck disable=SC1090
          . "$connection_env"
        fi

        if [ "$needs_url" -eq 1 ] && [ -n "''${OPENCLAW_GATEWAY_URL:-}" ]; then
          args+=(--url "$OPENCLAW_GATEWAY_URL")
        fi

        if [ "$needs_token" -eq 1 ] && [ -n "''${OPENCLAW_GATEWAY_TOKEN_FILE:-}" ] && [ -r "$OPENCLAW_GATEWAY_TOKEN_FILE" ]; then
          args+=(--token "$(cat "$OPENCLAW_GATEWAY_TOKEN_FILE")")
        fi

        exec "$real_openclaw" tui "''${args[@]}" "$@"
      fi

      exec "$real_openclaw" "$@"
    '';
  };
in {
  environment.sessionVariables = {
    OPENCLAW_CONTROL_UI_URL = "http://127.0.0.1:${toString gatewayPort}";
    OPENCLAW_GATEWAY_TOKEN_FILE = "${sshRunDir}/gateway-token";
    OPENCLAW_GATEWAY_URL = "ws://127.0.0.1:${toString gatewayPort}";
  };

  networking.networkmanager.unmanaged = [
    "interface-name:${bridgeName}"
    "interface-name:${tapName}"
  ];

  systemd.network = {
    enable = true;
    netdevs."10-${bridgeName}" = {
      netdevConfig = {
        Kind = "bridge";
        Name = bridgeName;
      };
    };
    networks."10-${bridgeName}" = {
      matchConfig.Name = bridgeName;
      address = ["${hostAddress}/24"];
      networkConfig = {
        ConfigureWithoutCarrier = true;
      };
      linkConfig = {
        RequiredForOnline = "no";
      };
    };
    networks."20-${tapName}" = {
      matchConfig.Name = tapName;
      networkConfig = {
        Bridge = bridgeName;
      };
      linkConfig = {
        RequiredForOnline = "no";
      };
    };
  };

  networking.nat = {
    enable = true;
    internalInterfaces = [bridgeName];
  };

  networking.firewall.interfaces.${bridgeName}.allowedTCPPorts = [ollamaPort];

  environment.systemPackages = [
    hostOpenClaw
    (pkgs.writeShellApplication {
      name = "ssh-openclaw-microvm";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.openssh
      ];
      text = ''
        ${lib.getExe refreshKnownHosts}

        tmpdir="$(mktemp -d)"
        trap 'rm -rf "$tmpdir"' EXIT

        install -m 0600 ${sshDir}/id_ed25519 "$tmpdir/id_ed25519"
        exec ssh \
          -F ${sshDir}/config \
          -o IdentityFile="$tmpdir/id_ed25519" \
          -o IdentitiesOnly=yes \
          openclaw-microvm \
          "$@"
      '';
    })
    (pkgs.writeShellApplication {
      name = "ssh-openclaw";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.openssh
      ];
      text = ''
        ${lib.getExe refreshKnownHosts}

        tmpdir="$(mktemp -d)"
        trap 'rm -rf "$tmpdir"' EXIT

        install -m 0600 ${sshDir}/id_ed25519 "$tmpdir/id_ed25519"
        exec ssh \
          -F ${sshDir}/config \
          -o IdentityFile="$tmpdir/id_ed25519" \
          -o IdentitiesOnly=yes \
          openclaw-microvm \
          "$@"
      '';
    })
    (pkgs.writeShellApplication {
      name = "scp-openclaw";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.openssh
      ];
      text = ''
        ${lib.getExe refreshKnownHosts}

        tmpdir="$(mktemp -d)"
        trap 'rm -rf "$tmpdir"' EXIT

        install -m 0600 ${sshDir}/id_ed25519 "$tmpdir/id_ed25519"
        exec scp \
          -F ${sshDir}/config \
          -o IdentityFile="$tmpdir/id_ed25519" \
          -o IdentitiesOnly=yes \
          "$@"
      '';
    })
    (pkgs.writeShellApplication {
      name = "openclaw-web";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.xdg-utils
      ];
      text = ''
        url="http://127.0.0.1:${toString gatewayPort}"

        if [ -r ${sshRunDir}/connection.env ]; then
          # shellcheck disable=SC1091
          . ${sshRunDir}/connection.env
          url="''${OPENCLAW_CONTROL_UI_URL:-$url}"
        fi

        if command -v xdg-open >/dev/null 2>&1; then
          exec xdg-open "$url"
        fi

        printf '%s\n' "$url"
      '';
    })
    (pkgs.writeShellApplication {
      name = "openclaw-ui";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        exec openclaw-web "$@"
      '';
    })
    (pkgs.writeShellApplication {
      name = "openclaw-tui";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        exec openclaw tui "$@"
      '';
    })
  ];

  systemd.services.openclaw-microvm-ssh-keygen = {
    description = "Generate host-side SSH credentials for the OpenClaw MicroVM";
    wantedBy = ["microvms.target"];
    before = [
      "microvm@${vmName}.service"
      "microvm-virtiofsd@${vmName}.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RuntimeDirectory = "openclaw-microvm";
      RuntimeDirectoryMode = "0755";
      RuntimeDirectoryPreserve = "yes";
    };
    script = ''
      install -d -m 0755 ${sshDir}
      install -d -m 0755 ${guestShareDir}

      if [ ! -s ${sshDir}/id_ed25519 ]; then
        ${lib.getExe' pkgs.openssh "ssh-keygen"} \
          -q \
          -t ed25519 \
          -N "" \
          -C "${vmName}@${config.networking.hostName}" \
          -f ${sshDir}/id_ed25519
      fi

      if [ ! -s ${sshRunDir}/gateway-token ]; then
        ${lib.getExe' pkgs.openssl "openssl"} rand -hex 32 > ${sshRunDir}/gateway-token
      fi

      install -m 0644 ${sshRunDir}/gateway-token ${guestShareDir}/gateway-token

      cat > ${sshDir}/config <<EOF
      Host openclaw-microvm
        HostName ${guestAddress}
        User openclaw
        StrictHostKeyChecking accept-new
        UserKnownHostsFile ${sshDir}/known_hosts
      EOF

      chmod 0644 ${sshDir}/config
      chmod 0644 ${sshDir}/id_ed25519
      chmod 0644 ${sshDir}/id_ed25519.pub
      if [ -e ${sshDir}/known_hosts ]; then
        chmod 0644 ${sshDir}/known_hosts
      fi
      install -m 0644 ${sshDir}/id_ed25519.pub ${guestShareDir}/authorized_key.pub

      cat > ${sshRunDir}/connection.env <<EOF
      OPENCLAW_VM_NAME=${vmName}
      OPENCLAW_VM_HOST=${guestAddress}
      OPENCLAW_VM_USER=openclaw
      OPENCLAW_VM_SSH_CONFIG=${sshDir}/config
      OPENCLAW_VM_SSH_KEY=${sshDir}/id_ed25519
      OPENCLAW_VM_SSH_TARGET=openclaw-microvm
      OPENCLAW_VM_SSH_COMMAND=ssh-openclaw
      OPENCLAW_GATEWAY_URL=ws://127.0.0.1:${toString gatewayPort}
      OPENCLAW_CONTROL_UI_URL=http://127.0.0.1:${toString gatewayPort}
      OPENCLAW_GATEWAY_TOKEN_FILE=${sshRunDir}/gateway-token
      OLLAMA_HOST_URL=http://${hostAddress}:${toString ollamaPort}
      OPENCLAW_CONFIG_PATH=/etc/openclaw/openclaw.json
      EOF

      cat > ${sshRunDir}/connection.json <<EOF
      ${builtins.toJSON {
        vm = {
          name = vmName;
          host = guestAddress;
          user = "openclaw";
        };
        ssh = {
          target = "openclaw-microvm";
          config = "${sshDir}/config";
          privateKey = "${sshDir}/id_ed25519";
          publicKey = "${sshDir}/id_ed25519.pub";
        };
        openclaw = {
          mode = "gateway";
          config = "/etc/openclaw/openclaw.json";
          gatewayUrl = "ws://127.0.0.1:${toString gatewayPort}";
          controlUiUrl = "http://127.0.0.1:${toString gatewayPort}";
          gatewayTokenFile = "${sshRunDir}/gateway-token";
        };
        ollama = {
          hostUrl = "http://${hostAddress}:${toString ollamaPort}";
        };
      }}
      EOF

      cat > ${sshRunDir}/README.txt <<EOF
      OpenClaw MicroVM runtime data

      SSH:
        ssh-openclaw

      OpenClaw:
        Gateway URL: ws://127.0.0.1:${toString gatewayPort}
        Control UI URL: http://127.0.0.1:${toString gatewayPort}
        Gateway token file: ${sshRunDir}/gateway-token
        Tunnel service: systemctl status openclaw-microvm-gateway-tunnel
        Browser helper: openclaw-web
        Host CLI helper: openclaw / openclaw-tui

        OpenClaw CLI is also installed inside the guest:
          ssh-openclaw openclaw

      Host Ollama endpoint:
        http://${hostAddress}:${toString ollamaPort}

      Metadata:
        ${sshRunDir}/connection.env
        ${sshRunDir}/connection.json
      EOF
    '';
  };

  systemd.services."microvm@${vmName}" = {
    after = ["openclaw-microvm-ssh-keygen.service"];
    requires = ["openclaw-microvm-ssh-keygen.service"];
  };

  systemd.services.openclaw-microvm-gateway-tunnel = {
    description = "Tunnel the OpenClaw gateway from the MicroVM to host loopback";
    wantedBy = ["multi-user.target"];
    after = [
      "openclaw-microvm-ssh-keygen.service"
      "microvm@${vmName}.service"
      "network-online.target"
    ];
    requires = [
      "openclaw-microvm-ssh-keygen.service"
      "microvm@${vmName}.service"
    ];
    wants = ["network-online.target"];
    serviceConfig = {
      Restart = "always";
      RestartSec = "2s";
    };
    script = ''
      ${lib.getExe refreshKnownHosts}

      tmpdir="$(mktemp -d)"
      trap 'rm -rf "$tmpdir"' EXIT

      install -m 0600 ${sshDir}/id_ed25519 "$tmpdir/id_ed25519"

      exec ${lib.getExe pkgs.openssh} \
        -N \
        -F ${sshDir}/config \
        -o IdentityFile="$tmpdir/id_ed25519" \
        -o IdentitiesOnly=yes \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -L 127.0.0.1:${toString gatewayPort}:127.0.0.1:${toString gatewayPort} \
        openclaw-microvm
    '';
  };

  systemd.services."microvm-virtiofsd@${vmName}" = {
    after = ["openclaw-microvm-ssh-keygen.service"];
    requires = ["openclaw-microvm-ssh-keygen.service"];
  };

  microvm.vms.${vmName} = {
    autostart = true;
    config = {
      networking.hostName = vmName;
      system.stateVersion = "25.05";

      users.groups.openclaw = {};
      users.users.openclaw = {
        isNormalUser = true;
        group = "openclaw";
        home = "/home/openclaw";
        createHome = true;
        description = "OpenClaw user";
        shell = pkgs.zsh;
      };

      programs.zsh.enable = true;
      environment.enableAllTerminfo = true;
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      networking.useDHCP = false;
      networking.usePredictableInterfaceNames = false;
      systemd.network = {
        enable = true;
        links."10-openclaw-uplink" = {
          matchConfig.MACAddress = "02:00:00:42:00:02";
          linkConfig.Name = "eth0";
        };
        networks."10-openclaw-uplink" = {
          matchConfig.Name = "eth0";
          address = ["${guestAddress}/24"];
          routes = [
            {
              Gateway = hostAddress;
              Destination = "0.0.0.0/0";
            }
          ];
          networkConfig.DNS = hostAddress;
        };
      };
      networking.nameservers = [hostAddress "1.1.1.1" "8.8.8.8"];
      networking.firewall.allowedTCPPorts = [22];

      environment.systemPackages = [
        guestOpenClaw
        llmPkgs.codex
        pkgs.bun
        pkgs.curl
        pkgs.fd
        pkgs.gh
        pkgs.git
        pkgs.gnumake
        pkgs.jq
        pkgs.neovim
        pkgs.postgresql
        pkgs.python3
        pkgs.python3Packages.ipython
        pkgs.ripgrep
        pkgs.unzip
        pkgs.uv
        pkgs.valkey
      ];

      environment.etc."openclaw/openclaw.json".source = openclawConfig;
      environment.variables = {
        OLLAMA_BASE_URL = "http://${hostAddress}:${toString ollamaPort}";
        OLLAMA_API_KEY = "ollama-local";
        OPENCLAW_CONFIG_PATH = "/etc/openclaw/openclaw.json";
        OPENCLAW_CONTROL_UI_URL = "http://127.0.0.1:${toString gatewayPort}";
        OPENCLAW_GATEWAY_TOKEN_FILE = "/run/host-share/gateway-token";
        OPENCLAW_GATEWAY_URL = "ws://127.0.0.1:${toString gatewayPort}";
        OPENCLAW_HOME = "/home/openclaw";
        OPENCLAW_STATE_DIR = "/var/lib/openclaw";
      };

      systemd.tmpfiles.rules = [
        "d /var/lib/openclaw 0750 openclaw openclaw -"
        "d /home/openclaw/workspace 0750 openclaw openclaw -"
      ];

      systemd.services.openclaw-gateway = {
        description = "Expose the OpenClaw gateway inside the MicroVM";
        after = ["install-host-ssh-key.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Environment = [
            "OPENCLAW_CONFIG_PATH=/etc/openclaw/openclaw.json"
            "OPENCLAW_HOME=/home/openclaw"
            "OPENCLAW_STATE_DIR=/var/lib/openclaw"
            "OLLAMA_BASE_URL=http://${hostAddress}:${toString ollamaPort}"
            "OLLAMA_API_KEY=ollama-local"
          ];
          User = "openclaw";
          Group = "openclaw";
          WorkingDirectory = "/home/openclaw";
          Restart = "always";
          RestartSec = "2s";
        };
        script = ''
          token="$(cat /run/host-share/gateway-token)"
          exec ${lib.getExe llmPkgs.openclaw} \
            gateway run \
            --allow-unconfigured \
            --bind loopback \
            --auth token \
            --token "$token" \
            --port ${toString gatewayPort}
        '';
      };

      systemd.services.install-host-ssh-key = {
        description = "Authorize the host-generated SSH key for openclaw";
        after = ["local-fs.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig.Type = "oneshot";
        script = ''
          install -d -m 0700 -o openclaw -g openclaw /home/openclaw/.ssh
          install -m 0600 -o openclaw -g openclaw /run/host-share/authorized_key.pub /home/openclaw/.ssh/authorized_keys
        '';
      };

      microvm = {
        hypervisor = "cloud-hypervisor";
        vsock.cid = 42;
        vcpu = 4;
        mem = 6144;
        interfaces = [
          {
            type = "tap";
            id = tapName;
            mac = "02:00:00:42:00:02";
          }
        ];
        shares = [
          {
            proto = "virtiofs";
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
          }
          {
            proto = "virtiofs";
            tag = "host-share";
            source = guestShareDir;
            mountPoint = "/run/host-share";
            readOnly = true;
          }
        ];
        volumes = [
          {
            image = "openclaw-state.img";
            mountPoint = "/var/lib/openclaw";
            size = 4096;
          }
        ];
      };
    };
  };
}
