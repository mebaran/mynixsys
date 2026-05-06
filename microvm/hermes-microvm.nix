{
  config,
  lib,
  pkgs,
  hermes,
  llm-agents,
  ...
}: let
  cfg = config.services.hermesMicrovm;
in {
  options.services.hermesMicrovm = {
    enable = lib.mkEnableOption "Hermes Agent MicroVM service";

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the Hermes MicroVM with microvms.target.";
    };

    bridgeName = lib.mkOption {
      type = lib.types.str;
      default = "microvm";
      description = "Bridge used for the Hermes MicroVM tap interface.";
    };

    hostAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.10.10.1/24";
      description = "IPv4 address assigned to the MicroVM bridge on the host.";
    };

    gatewayAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.10.10.1";
      description = "IPv4 gateway address used by the Hermes MicroVM.";
    };

    guestAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.10.10.2";
      description = "Static IPv4 address assigned to the Hermes MicroVM.";
    };

    tapPattern = lib.mkOption {
      type = lib.types.str;
      default = "vm-*";
      description = "Host interface name pattern for MicroVM tap devices.";
    };

    externalInterface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "enp1s0";
      description = "Optional uplink interface used for NAT from the bridge to the outside network.";
    };

    profiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
        options = {
          environmentDirectory = lib.mkOption {
            type = lib.types.path;
            default = "/var/lib/hermes-agent/profiles/${name}/env.d";
            description = ''
              Host-managed directory of .env files for the ${name} Hermes profile.
            '';
          };

          homeDirectory = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/hermes/profiles/${name}";
            description = ''
              Guest-side HERMES_HOME for this profile. Use /var/lib/hermes for
              the orchestrator profile that owns the shared Kanban board.
            '';
          };

          model = lib.mkOption {
            type = lib.types.attrs;
            default = {
              provider = "openai-codex";
              default = "gpt-5.3-codex";
            };
            example = {
              provider = "openrouter";
              default = "anthropic/claude-sonnet-4.6";
            };
            description = ''
              Hermes model configuration written to this profile's config.yaml.
              Secrets still belong in the profile environmentDirectory.
            '';
          };

          externalSkillDirectories = lib.mkOption {
            type = lib.types.listOf lib.types.path;
            default = [];
            example = [./hermes-skills/common];
            description = ''
              Baked Hermes skill directories exposed to this profile through
              skills.external_dirs in config.yaml.
            '';
          };

          workspaceDirectories = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            example = [
              "repos"
              "requests"
              "scratch"
            ];
            description = ''
              Generic subdirectories created under this profile's workspace.
              Keep project and repository names out of Nix; create or clone them
              at runtime inside these workspace directories.
            '';
          };

          apiServer = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable the Hermes API server gateway for this profile.";
            };

            host = lib.mkOption {
              type = lib.types.str;
              default = "0.0.0.0";
              description = "Address the Hermes API server binds inside the guest.";
            };

            port = lib.mkOption {
              type = lib.types.port;
              description = "TCP port for this profile's Hermes API server.";
            };

            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Open this profile's API server port in the guest firewall.";
            };
          };

          webhook = {
            port = lib.mkOption {
              type = lib.types.port;
              description = "TCP port reserved for this profile's generic webhook gateway.";
            };

            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Open this profile's webhook port in the guest firewall.";
            };
          };
        };
      }));
      default = {};
      description = "Named Hermes profiles to run inside the MicroVM.";
    };

    hostProxy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Proxy Hermes profile ports from the host to the MicroVM.";
      };

      bindAddress = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Host address used by the Hermes proxy sockets.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open proxied Hermes profile ports in the host firewall.";
      };
    };
  };

  config = lib.mkIf cfg.enable (let
    proxiedProfiles = lib.filterAttrs (_: profile: profile.apiServer.enable) cfg.profiles;
    proxiedApiPorts = lib.mapAttrsToList (_: profile: profile.apiServer.port) proxiedProfiles;
    proxiedWebhookPorts = lib.mapAttrsToList (_: profile: profile.webhook.port) cfg.profiles;
    proxiedPorts = lib.unique (proxiedApiPorts ++ proxiedWebhookPorts);
  in {
    environment.systemPackages = let
      sshHermesMicrovm = pkgs.writeShellApplication {
        name = "ssh-hermes-microvm";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.openssh
        ];
        text = ''
          tmpdir="$(mktemp -d)"
          trap 'rm -rf "$tmpdir"' EXIT

          install -m 0600 /var/lib/hermes-agent/host "$tmpdir/host"

          exec ssh \
            -F /dev/null \
            -o IdentityFile="$tmpdir/host" \
            -o IdentitiesOnly=yes \
            -o StrictHostKeyChecking=accept-new \
            -o UserKnownHostsFile="$tmpdir/known_hosts" \
            root@${cfg.guestAddress} \
            "$@"
        '';
      };

      codexProfileCases = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: profile: ''
          ${lib.escapeShellArg name})
            home=${lib.escapeShellArg profile.homeDirectory}
            ;;
        '')
        cfg.profiles);
      awsLoginProfiles = lib.filter (name: lib.hasAttr name cfg.profiles) ["orchestrator" "coder"];
      awsProfileCases = lib.concatStringsSep "\n" (map (name: ''
          ${lib.escapeShellArg name})
            home=${lib.escapeShellArg cfg.profiles.${name}.homeDirectory}
            ;;
        '')
        awsLoginProfiles);

      hermesCodexLogin = pkgs.writeShellApplication {
        name = "hermes-codex-login";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.openssh
        ];
        text = ''
          profile="''${1:-orchestrator}"
          mode="''${2:-login}"

          case "$profile" in
          ${codexProfileCases}
          *)
            echo "Unknown Hermes profile: $profile" >&2
            echo "Known profiles: ${lib.concatStringsSep " " (lib.attrNames cfg.profiles)}" >&2
            exit 2
            ;;
          esac

          case "$mode" in
            login)
              hermes_args="auth add openai-codex --type oauth"
              ;;
            status)
              hermes_args="auth status openai-codex"
              ;;
            logout)
              hermes_args="auth logout openai-codex"
              ;;
            *)
              echo "Usage: hermes-codex-login [${lib.concatStringsSep "|" (lib.attrNames cfg.profiles)}] [login|status|logout]" >&2
              exit 2
              ;;
          esac

          tmpdir="$(mktemp -d)"
          trap 'rm -rf "$tmpdir"' EXIT

          install -m 0600 /var/lib/hermes-agent/host "$tmpdir/host"

          user_home="$home/home"
          remote_inner="set -a && [ ! -r $home/.env ] || . $home/.env && set +a && HERMES_HOME=$home HERMES_KANBAN_HOME=/var/lib/hermes HOME=$user_home exec hermes $hermes_args"
          quoted_home="$(printf '%q' "$home")"
          quoted_user_home="$(printf '%q' "$user_home")"
          quoted_inner="$(printf '%q' "$remote_inner")"
          remote_command="install -d -m 0750 -o hermes -g hermes $quoted_home $quoted_user_home && su -s /bin/sh hermes -c $quoted_inner"

          exec ssh \
            -t \
            -F /dev/null \
            -o IdentityFile="$tmpdir/host" \
            -o IdentitiesOnly=yes \
            -o StrictHostKeyChecking=accept-new \
            -o UserKnownHostsFile="$tmpdir/known_hosts" \
            root@${cfg.guestAddress} \
            "$remote_command"
        '';
      };

      hermesAwsLogin = pkgs.writeShellApplication {
        name = "hermes-aws-login";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.openssh
        ];
        text = ''
          profile="''${1:-orchestrator}"
          if [ "$#" -gt 0 ]; then
            shift
          fi
          mode="''${1:-login}"
          if [ "$#" -gt 0 ]; then
            shift
          fi

          case "$profile" in
          ${awsProfileCases}
          *)
            echo "Unknown AWS-enabled Hermes profile: $profile" >&2
            echo "Known AWS-enabled profiles: ${lib.concatStringsSep " " awsLoginProfiles}" >&2
            exit 2
            ;;
          esac

          case "$mode" in
            configure)
              aws_args=(configure)
              ;;
            login)
              aws_args=(configure)
              ;;
            status)
              aws_args=(sts get-caller-identity)
              ;;
            sso-configure)
              aws_args=(configure sso)
              ;;
            sso-login)
              aws_args=(sso login)
              ;;
            sso-logout)
              aws_args=(sso logout)
              ;;
            logout)
              echo "Static AWS credentials do not have a logout flow." >&2
              echo "Edit or remove '$home/home/.aws/credentials' if you need to clear them." >&2
              exit 2
              ;;
            *)
              echo "Usage: hermes-aws-login [${lib.concatStringsSep "|" awsLoginProfiles}] [configure|login|status|logout|sso-configure|sso-login|sso-logout] [aws args...]" >&2
              exit 2
              ;;
          esac

          aws_command="aws"
          for arg in "''${aws_args[@]}" "$@"; do
            aws_command="$aws_command $(printf '%q' "$arg")"
          done

          tmpdir="$(mktemp -d)"
          trap 'rm -rf "$tmpdir"' EXIT

          install -m 0600 /var/lib/hermes-agent/host "$tmpdir/host"

          user_home="$home/home"
          remote_inner="set -a && [ ! -r $home/.env ] || . $home/.env && set +a && HOME=$user_home AWS_CONFIG_FILE=$user_home/.aws/config AWS_SHARED_CREDENTIALS_FILE=$user_home/.aws/credentials exec $aws_command"
          quoted_user_home="$(printf '%q' "$user_home")"
          quoted_inner="$(printf '%q' "$remote_inner")"
          remote_command="install -d -m 0750 -o hermes -g hermes $quoted_user_home $quoted_user_home/.aws && su -s /bin/sh hermes -c $quoted_inner"

          exec ssh \
            -t \
            -F /dev/null \
            -o IdentityFile="$tmpdir/host" \
            -o IdentitiesOnly=yes \
            -o StrictHostKeyChecking=accept-new \
            -o UserKnownHostsFile="$tmpdir/known_hosts" \
            root@${cfg.guestAddress} \
            "$remote_command"
        '';
      };

      hermesContainerExec = pkgs.writeShellApplication {
        name = "hermes-container";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.openssh
        ];
        text = ''
          profile="''${1:-orchestrator}"
          if [ "$#" -gt 0 ]; then
            shift
          fi

          case "$profile" in
          ${codexProfileCases}
          *)
            echo "Unknown Hermes profile: $profile" >&2
            echo "Known profiles: ${lib.concatStringsSep " " (lib.attrNames cfg.profiles)}" >&2
            exit 2
            ;;
          esac

          if [ "$#" -eq 0 ]; then
            set -- hermes --tui
          fi

          command=""
          for arg in "$@"; do
            command="$command $(printf '%q' "$arg")"
          done

          tmpdir="$(mktemp -d)"
          trap 'rm -rf "$tmpdir"' EXIT

          install -m 0600 /var/lib/hermes-agent/host "$tmpdir/host"

          user_home="$home/home"
          remote_inner="cd $home/workspace && set -a && [ ! -r $home/.env ] || . $home/.env && set +a && HERMES_HOME=$home HERMES_KANBAN_HOME=/var/lib/hermes HOME=$user_home exec $command"
          quoted_home="$(printf '%q' "$home")"
          quoted_user_home="$(printf '%q' "$user_home")"
          quoted_workspace="$(printf '%q' "$home/workspace")"
          quoted_inner="$(printf '%q' "$remote_inner")"
          remote_command="install -d -m 0750 -o hermes -g hermes $quoted_home $quoted_user_home $quoted_workspace && su -s /bin/sh hermes -c $quoted_inner"

          exec ssh \
            -t \
            -F /dev/null \
            -o IdentityFile="$tmpdir/host" \
            -o IdentitiesOnly=yes \
            -o StrictHostKeyChecking=accept-new \
            -o UserKnownHostsFile="$tmpdir/known_hosts" \
            root@${cfg.guestAddress} \
            "$remote_command"
        '';
      };

      profileTuiWrappers = lib.mapAttrsToList (name: profile: let
        hermesArgs = ["hermes" "--tui"];
        tuiCommand = "cd ${profile.homeDirectory}/workspace && set -a && [ ! -r ${profile.homeDirectory}/.env ] || . ${profile.homeDirectory}/.env && set +a && HERMES_HOME=${profile.homeDirectory} HOME=${profile.homeDirectory}/home exec ${lib.escapeShellArgs hermesArgs}";
        remoteCommand = "su -s /bin/sh hermes -c ${lib.escapeShellArg tuiCommand}";
      in
        pkgs.writeShellApplication {
          name = "hermes-${name}";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.openssh
          ];
          text = ''
            tmpdir="$(mktemp -d)"
            trap 'rm -rf "$tmpdir"' EXIT

            install -m 0600 /var/lib/hermes-agent/host "$tmpdir/host"

            exec ssh \
              -t \
              -F /dev/null \
              -o IdentityFile="$tmpdir/host" \
              -o IdentitiesOnly=yes \
              -o StrictHostKeyChecking=accept-new \
              -o UserKnownHostsFile="$tmpdir/known_hosts" \
              root@${cfg.guestAddress} \
              ${lib.escapeShellArg remoteCommand}
          '';
        })
      cfg.profiles;
    in
      [
        sshHermesMicrovm
        hermesAwsLogin
        hermesCodexLogin
        hermesContainerExec
      ]
      ++ profileTuiWrappers;

    networking.networkmanager.unmanaged = [
      "interface-name:${cfg.bridgeName}"
      "interface-name:vm-hermes"
    ];

    networking.useNetworkd = true;
    systemd.network.enable = true;

    systemd.tmpfiles.rules =
      [
        "d /var/lib/hermes-agent 0755 root root - -"
        "d /var/lib/hermes-agent/authorized_keys.d 0755 root root - -"
      ]
      ++ lib.concatMap (profile: [
        "d ${builtins.dirOf profile.environmentDirectory} 0755 root root - -"
        "d ${profile.environmentDirectory} 0755 root root - -"
      ]) (lib.attrValues cfg.profiles);

    systemd.network.netdevs."10-${cfg.bridgeName}" = {
      netdevConfig = {
        Kind = "bridge";
        Name = cfg.bridgeName;
      };
    };

    systemd.network.networks."10-${cfg.bridgeName}" = {
      matchConfig.Name = cfg.bridgeName;
      address = [cfg.hostAddress];
      networkConfig = {
        DHCPServer = true;
        IPv6SendRA = true;
        ConfigureWithoutCarrier = true;
      };
      linkConfig.RequiredForOnline = "no";
    };

    systemd.network.networks."11-${cfg.bridgeName}-tap" = {
      matchConfig.Name = cfg.tapPattern;
      networkConfig.Bridge = cfg.bridgeName;
      linkConfig.RequiredForOnline = "no";
    };

    networking.firewall.allowedUDPPorts = [67];
    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.hostProxy.enable && cfg.hostProxy.openFirewall) proxiedPorts;

    systemd.sockets =
      lib.mkIf cfg.hostProxy.enable
      (lib.mkMerge [
        (lib.mapAttrs' (name: profile:
          lib.nameValuePair "hermes-${name}-api-proxy" {
            description = "Proxy Hermes ${name} API traffic to the MicroVM";
            wantedBy = ["sockets.target"];
            listenStreams = ["${cfg.hostProxy.bindAddress}:${toString profile.apiServer.port}"];
            socketConfig = {
              NoDelay = true;
            };
          })
        proxiedProfiles)

        (lib.mapAttrs' (name: profile:
          lib.nameValuePair "hermes-${name}-webhook-proxy" {
            description = "Proxy Hermes ${name} webhook traffic to the MicroVM";
            wantedBy = ["sockets.target"];
            listenStreams = ["${cfg.hostProxy.bindAddress}:${toString profile.webhook.port}"];
            socketConfig = {
              NoDelay = true;
            };
          })
        cfg.profiles)
      ]);

    networking.nat =
      {
        enable = true;
        enableIPv6 = true;
        internalInterfaces = [cfg.bridgeName];
      }
      // lib.optionalAttrs (cfg.externalInterface != null) {
        externalInterface = cfg.externalInterface;
      };

    systemd.services = lib.mkMerge [
      (lib.mkIf cfg.hostProxy.enable
        (lib.mkMerge [
          (lib.mapAttrs' (name: profile:
            lib.nameValuePair "hermes-${name}-api-proxy" {
              description = "Proxy Hermes ${name} API traffic to the MicroVM";
              after = [
                "microvm@hermes.service"
                "network-online.target"
              ];
              requires = ["microvm@hermes.service"];
              wants = ["network-online.target"];
              serviceConfig = {
                ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd ${cfg.guestAddress}:${toString profile.apiServer.port}";
                DynamicUser = true;
                PrivateTmp = true;
              };
            })
          proxiedProfiles)

          (lib.mapAttrs' (name: profile:
            lib.nameValuePair "hermes-${name}-webhook-proxy" {
              description = "Proxy Hermes ${name} webhook traffic to the MicroVM";
              after = [
                "microvm@hermes.service"
                "network-online.target"
              ];
              requires = ["microvm@hermes.service"];
              wants = ["network-online.target"];
              serviceConfig = {
                ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd ${cfg.guestAddress}:${toString profile.webhook.port}";
                DynamicUser = true;
                PrivateTmp = true;
              };
            })
          cfg.profiles)
        ]))

      {
        hermes-microvm-ssh-keygen = {
          description = "Generate host-side SSH credentials for the Hermes MicroVM";
          wantedBy = ["microvms.target"];
          before = [
            "microvm@hermes.service"
            "microvm-virtiofsd@hermes.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            install -d -m 0755 /var/lib/hermes-agent/authorized_keys.d

            if [ ! -s /var/lib/hermes-agent/host ]; then
              ${lib.getExe' pkgs.openssh "ssh-keygen"} \
                -q \
                -t ed25519 \
                -N "" \
                -C "hermes@${config.networking.hostName}" \
                -f /var/lib/hermes-agent/host
            fi

            install -m 0644 /var/lib/hermes-agent/host.pub /var/lib/hermes-agent/authorized_keys.d/host.pub
            chown root:users /var/lib/hermes-agent/host
            chown root:root /var/lib/hermes-agent/host.pub
            chmod 0640 /var/lib/hermes-agent/host
          '';
        };

        "microvm@hermes" = {
          after = ["hermes-microvm-ssh-keygen.service"];
          requires = ["hermes-microvm-ssh-keygen.service"];
        };

        "microvm-virtiofsd@hermes" = {
          after = ["hermes-microvm-ssh-keygen.service"];
          requires = ["hermes-microvm-ssh-keygen.service"];
        };
      }
    ];

    microvm.vms.hermes = {
      inherit (cfg) autostart;
      specialArgs = {
        inherit llm-agents;
        hermesProfiles = cfg.profiles;
      };
      config = {
        imports = [
          hermes.nixosModules.default
          ./hermes-guest.nix
        ];

        microvm.shares =
          lib.mapAttrsToList (name: profile: {
            proto = "virtiofs";
            tag = "host-hermes-env-${name}";
            source = profile.environmentDirectory;
            mountPoint = "/run/host-hermes-profiles/${name}/env.d";
          })
          cfg.profiles;

        networking.useDHCP = lib.mkForce false;
        networking.usePredictableInterfaceNames = false;
        systemd.network.links."10-hermes-uplink" = {
          matchConfig.MACAddress = "02:00:00:01:01:01";
          linkConfig.Name = "eth0";
        };
        systemd.network.networks."20-uplink" = {
          matchConfig.Name = "eth0";
          address = ["${cfg.guestAddress}/24"];
          routes = [
            {
              Gateway = cfg.gatewayAddress;
              Destination = "0.0.0.0/0";
            }
          ];
          networkConfig = {
            DHCP = lib.mkForce "no";
            DNS = cfg.gatewayAddress;
            IPv6AcceptRA = false;
          };
          linkConfig.RequiredForOnline = "routable";
        };
        networking.nameservers = [
          cfg.gatewayAddress
          "1.1.1.1"
          "8.8.8.8"
        ];
      };
    };
  });
}
