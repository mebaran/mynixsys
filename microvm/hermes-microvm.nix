{ config, lib, pkgs, hermes, ... }:

let
  cfg = config.services.hermesMicrovm;
in
{
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
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager.unmanaged = [
      "interface-name:${cfg.bridgeName}"
      "interface-name:vm-hermes"
    ];

    networking.useNetworkd = true;
    systemd.network.enable = true;

    systemd.tmpfiles.rules = [
      "d /var/lib/hermes-agent 0755 root root - -"
      "d /var/lib/hermes-agent/authorized_keys.d 0755 root root - -"
    ];

    systemd.network.netdevs."10-${cfg.bridgeName}" = {
      netdevConfig = {
        Kind = "bridge";
        Name = cfg.bridgeName;
      };
    };

    systemd.network.networks."10-${cfg.bridgeName}" = {
      matchConfig.Name = cfg.bridgeName;
      addresses = [
        {
          addressConfig.Address = cfg.hostAddress;
        }
      ];
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

    networking.firewall.allowedUDPPorts = [ 67 ];

    networking.nat =
      {
        enable = true;
        enableIPv6 = true;
        internalInterfaces = [ cfg.bridgeName ];
      }
      // lib.optionalAttrs (cfg.externalInterface != null) {
        externalInterface = cfg.externalInterface;
      };

    systemd.services.hermes-microvm-ssh-keygen = {
      description = "Generate host-side SSH credentials for the Hermes MicroVM";
      wantedBy = [ "microvms.target" ];
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
      '';
    };

    systemd.services."microvm@hermes" = {
      after = [ "hermes-microvm-ssh-keygen.service" ];
      requires = [ "hermes-microvm-ssh-keygen.service" ];
    };

    systemd.services."microvm-virtiofsd@hermes" = {
      after = [ "hermes-microvm-ssh-keygen.service" ];
      requires = [ "hermes-microvm-ssh-keygen.service" ];
    };

    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "ssh-hermes-microvm";
        runtimeInputs = [ pkgs.openssh ];
        text = ''
          exec ssh \
            -o IdentityFile=/var/lib/hermes-agent/host \
            -o IdentitiesOnly=yes \
            -o StrictHostKeyChecking=accept-new \
            root@${cfg.guestAddress} \
            "$@"
        '';
      })
    ];

    microvm.vms.hermes = {
      inherit (cfg) autostart;
      config = {
        imports = [
          hermes.nixosModules.default
          ./hermes-guest.nix
        ];

        networking.useDHCP = lib.mkForce false;
        networking.usePredictableInterfaceNames = false;
        systemd.network.links."10-hermes-uplink" = {
          matchConfig.MACAddress = "02:00:00:01:01:01";
          linkConfig.Name = "eth0";
        };
        systemd.network.networks."20-uplink" = {
          matchConfig.Name = "eth0";
          address = [ "${cfg.guestAddress}/24" ];
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
  };
}
