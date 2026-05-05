{
  config,
  lib,
  pkgs,
  llm-agents,
  hermesProfiles ? {},
  ...
}: let
  hostAuthorizedKeysDir = "/var/lib/hermes-agent/authorized_keys.d";
  guestAuthorizedKeysDir = "/run/host-authorized-keys";
  guestProfilesDir = "/run/host-hermes-profiles";

  llmPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  hermesPackage = config.services.hermes-agent.package;
  profileNames = lib.attrNames hermesProfiles;

  baseSettings = {
    terminal.backend = "local";
    toolsets = ["all"];
    platform_toolsets = {
      cli = ["hermes-cli"];
      api_server = [
        "hermes-api-server"
        "kanban"
      ];
      webhook = ["hermes-webhook"];
    };
    kanban = {
      dispatch_in_gateway = true;
    };
  };

  profileHome = name: hermesProfiles.${name}.homeDirectory;
  profileEnvDir = name: "${guestProfilesDir}/${name}/env.d";
  profileSettings = name: profile:
    baseSettings
    // {
      model = profile.model;
    }
    // lib.optionalAttrs (profile.externalSkillDirectories != []) {
      skills.external_dirs = profile.externalSkillDirectories;
    };
  profileConfigFile = name: profile:
    (pkgs.formats.yaml {}).generate "hermes-${name}-config.yaml" (profileSettings name profile);

  sysPkgs = with pkgs; [
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
  aiPkgs = with llmPkgs; [
    codex
    opencode
  ];
in {
  system.stateVersion = "25.05";

  networking.hostName = "hermes-vm";
  networking.firewall.allowedTCPPorts =
    [22]
    ++ lib.concatMap (profile:
      lib.optional (profile.apiServer.enable && profile.apiServer.openFirewall) profile.apiServer.port
      ++ lib.optional profile.webhook.openFirewall profile.webhook.port)
    (lib.attrValues hermesProfiles);
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

  users.groups.hermes = {};
  users.users.hermes = {
    isSystemUser = true;
    group = "hermes";
    home = "/var/lib/hermes";
    createHome = true;
    shell = pkgs.bashInteractive;
  };

  environment.systemPackages = sysPkgs ++ aiPkgs ++ [hermesPackage];
  environment.variables = {
    HERMES_HOME = "/var/lib/hermes";
    HERMES_KANBAN_HOME = "/var/lib/hermes";
  };

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

  systemd.tmpfiles.rules =
    [
      "d /var/lib/hermes 0750 hermes hermes - -"
      "d /var/lib/hermes/profiles 0750 hermes hermes - -"
      "d /root/.ssh 0700 root root - -"
    ]
    ++ lib.concatMap (name: let
      home = profileHome name;
    in
      [
        "d ${home} 0750 hermes hermes - -"
        "d ${home}/home 0750 hermes hermes - -"
        "d ${home}/codex 0750 hermes hermes - -"
        "d ${home}/workspace 0750 hermes hermes - -"
        "d ${home}/logs 0750 hermes hermes - -"
        "f ${home}/.env 0600 hermes hermes - -"
        "f ${home}/host.env 0600 hermes hermes - -"
        "f ${home}/local.env 0600 hermes hermes - -"
      ]
      ++ lib.map (dir: "d ${home}/workspace/${dir} 0750 hermes hermes - -") hermesProfiles.${name}.workspaceDirectories)
    profileNames;

  systemd.services =
    {
      install-host-authorized-keys = {
        description = "Install SSH authorized keys from the host share";
        wantedBy = ["multi-user.target"];
        before = ["sshd.service"];
        after = ["local-fs.target"];
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
    }
    // lib.mapAttrs' (name: profile: let
      home = profileHome name;
      envDir = profileEnvDir name;
    in
      lib.nameValuePair "install-host-hermes-env-${name}" {
        description = "Install Hermes environment files for the ${name} profile";
        requiredBy = ["hermes-agent-${name}.service"];
        before = ["hermes-agent-${name}.service"];
        after = ["local-fs.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -eu

          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg home}
          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/home"}
          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/codex"}
          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/workspace"}
          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/logs"}
          ${lib.concatMapStringsSep "\n" (dir: "install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/workspace/${dir}"}") hermesProfiles.${name}.workspaceDirectories}
          install -m 0640 -o hermes -g hermes ${profileConfigFile name profile} ${lib.escapeShellArg "${home}/config.yaml"}

          host_tmp="$(mktemp)"
          env_tmp="$(mktemp)"
          trap 'rm -f "$host_tmp" "$env_tmp"' EXIT

          if [ -d ${lib.escapeShellArg envDir} ]; then
            find ${lib.escapeShellArg envDir} -maxdepth 1 -type f -name '*.env' -print0 \
              | sort -z \
              | xargs -0r cat -- > "$host_tmp"
          else
            : > "$host_tmp"
          fi

          install -m 0600 -o hermes -g hermes "$host_tmp" ${lib.escapeShellArg "${home}/host.env"}
          if [ ! -e ${lib.escapeShellArg "${home}/local.env"} ]; then
            install -m 0600 -o hermes -g hermes /dev/null ${lib.escapeShellArg "${home}/local.env"}
          fi

          {
            cat "$host_tmp"
            printf '\n'
            cat ${lib.escapeShellArg "${home}/local.env"}
          } > "$env_tmp"
          install -m 0600 -o hermes -g hermes "$env_tmp" ${lib.escapeShellArg "${home}/.env"}
        '';
      })
    hermesProfiles
    // lib.mapAttrs' (name: profile: let
      home = profileHome name;
    in
      lib.nameValuePair "hermes-agent-${name}" {
        description = "Hermes Agent Gateway (${name})";
        wantedBy = ["multi-user.target"];
        after = [
          "network-online.target"
          "install-host-hermes-env-${name}.service"
        ];
        wants = ["network-online.target"];
        requires = ["install-host-hermes-env-${name}.service"];
        environment = {
          HERMES_HOME = home;
          HERMES_KANBAN_HOME = "/var/lib/hermes";
          CODEX_HOME = "${home}/codex";
          HOME = "${home}/home";
          API_SERVER_ENABLED = lib.boolToString profile.apiServer.enable;
          API_SERVER_HOST = profile.apiServer.host;
          API_SERVER_PORT = toString profile.apiServer.port;
          WEBHOOK_PORT = toString profile.webhook.port;
        };
        path = [
          hermesPackage
          pkgs.bash
          pkgs.coreutils
          pkgs.git
          pkgs.openssh
        ];
        serviceConfig = {
          Type = "simple";
          User = "hermes";
          Group = "hermes";
          WorkingDirectory = "${home}/workspace";
          EnvironmentFile = [
            "${home}/.env"
          ];
          ExecStart = "${lib.getExe hermesPackage} gateway run --replace";
          Restart = "always";
          RestartSec = 5;
          UMask = "0007";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = false;
          ProtectSystem = "strict";
          ReadWritePaths = [home];
        };
      })
    hermesProfiles;

  services.hermes-agent = {
    enable = false;
    addToSystemPackages = true;
    settings = baseSettings;
  };
}
