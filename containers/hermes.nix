{
  config,
  lib,
  pkgs,
  hermes,
  llm-agents,
  ...
}: let
  cfg = config.services.hermesContainer;
in {
  options.services.hermesContainer = {
    enable = lib.mkEnableOption "Hermes Agent Podman container";

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the Hermes container at boot.";
    };

    containerName = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = "Podman container name used for Hermes services.";
    };

    dataDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/hermes";
      description = "Host directory mounted at /var/lib/hermes in the container.";
    };

    dashboard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the hermes-web helper for opening a profile dashboard.";
      };

      profile = lib.mkOption {
        type = lib.types.str;
        default = "orchestrator";
        description = "Profile used by the hermes-web helper.";
      };
    };

    profiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
        options = {
          environmentDirectory = lib.mkOption {
            type = lib.types.path;
            default = "/var/lib/hermes-agent/profiles/${name}/env.d";
            description = "Host-managed directory of .env files for this Hermes profile.";
          };

          homeDirectory = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/hermes/profiles/${name}";
            description = "Container-side HERMES_HOME for this profile.";
          };

          model = lib.mkOption {
            type = lib.types.attrs;
            default = {
              provider = "openai-codex";
              default = "gpt-5.3-codex";
            };
            description = "Hermes model configuration written to this profile's config.yaml.";
          };

          externalSkillDirectories = lib.mkOption {
            type = lib.types.listOf lib.types.path;
            default = [];
            description = "Baked Hermes skill directories exposed through skills.external_dirs.";
          };

          workspaceDirectories = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Subdirectories created under this profile's workspace.";
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
              description = "Address the Hermes API server binds inside the container.";
            };

            port = lib.mkOption {
              type = lib.types.port;
              description = "TCP port for this profile's Hermes API server.";
            };

            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Open this profile's API server port on the host.";
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
              description = "Open this profile's webhook port on the host.";
            };
          };

          dashboard = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Run the Hermes web dashboard for this profile.";
            };

            port = lib.mkOption {
              type = lib.types.port;
              description = "TCP port for this profile's Hermes web dashboard.";
            };

            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Open this profile's dashboard port on the host.";
            };
          };
        };
      }));
      default = {};
      description = "Named Hermes profiles to run in the container.";
    };
  };

  config = lib.mkIf cfg.enable (let
    llmPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
    hermesPackage = hermes.packages.${pkgs.stdenv.hostPlatform.system}.default;

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
      kanban.dispatch_in_gateway = true;
    };

    profileSettings = _name: profile:
      baseSettings
      // {
        model = profile.model;
      }
      // lib.optionalAttrs (profile.externalSkillDirectories != []) {
        skills.external_dirs = profile.externalSkillDirectories;
      };

    profileConfigFile = name: profile:
      (pkgs.formats.yaml {}).generate "hermes-${name}-config.yaml" (profileSettings name profile);

    path = lib.makeBinPath [
      hermesPackage
      llmPkgs.codex
      llmPkgs.opencode
      pkgs.bash
      pkgs.bun
      pkgs.cacert
      pkgs.coreutils
      pkgs.curl
      pkgs.duckdb
      pkgs.findutils
      pkgs.gawk
      pkgs.gh
      pkgs.git
      pkgs.gnused
      pkgs.htop
      pkgs.jq
      pkgs.openssh
      pkgs.s6
      pkgs.s6-linux-utils
      pkgs.uv
      pkgs.vim
    ];

    runAsHermes = "${pkgs.s6}/bin/s6-applyuidgid -u 1000 -g 1000 -G 1000";

    serviceTree = pkgs.runCommand "hermes-s6-services" {} ''
      set -eu
      mkdir -p "$out"
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: profile: let
          home = profile.homeDirectory;
          envDir = "/run/host-hermes-profiles/${name}/env.d";
          workspaceDirs =
            lib.concatMapStringsSep "\n" (dir: ''
              install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/workspace/${dir}"}
            '')
            profile.workspaceDirectories;
        in ''
          mkdir -p "$out/hermes-${name}/log"

          cat > "$out/hermes-${name}/run" <<'EOF'
          #!${pkgs.runtimeShell}
          set -eu
          export PATH=${lib.escapeShellArg path}
          export HERMES_HOME=${lib.escapeShellArg home}
          export HERMES_KANBAN_HOME=/var/lib/hermes
          export CODEX_HOME=${lib.escapeShellArg "${home}/codex"}
          export HOME=${lib.escapeShellArg "${home}/home"}
          export API_SERVER_ENABLED=${lib.escapeShellArg (lib.boolToString profile.apiServer.enable)}
          export API_SERVER_HOST=${lib.escapeShellArg profile.apiServer.host}
          export API_SERVER_PORT=${lib.escapeShellArg (toString profile.apiServer.port)}
          export WEBHOOK_PORT=${lib.escapeShellArg (toString profile.webhook.port)}

          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg home}
          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/home"}
          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/codex"}
          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/workspace"}
          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/logs"}
          ${workspaceDirs}
          install -m 0640 -o hermes -g hermes ${profileConfigFile name profile} ${lib.escapeShellArg "${home}/config.yaml"}

          setup_lock=${lib.escapeShellArg "${home}/.setup.lock"}
          while ! mkdir "$setup_lock" 2>/dev/null; do
            sleep 0.1
          done

          host_tmp="$(mktemp)"
          env_tmp="$(mktemp)"
          trap 'rm -f "$host_tmp" "$env_tmp"; rmdir "$setup_lock"' EXIT

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

          set -a
          . ${lib.escapeShellArg "${home}/.env"}
          set +a

          trap - EXIT
          rm -f "$host_tmp" "$env_tmp"
          rmdir "$setup_lock"

          exec 2>&1
          exec ${runAsHermes} ${lib.getExe hermesPackage} gateway run --replace
          EOF

          cat > "$out/hermes-${name}/log/run" <<'EOF'
          #!${pkgs.runtimeShell}
          exec ${pkgs.gawk}/bin/awk '{ print "[hermes-${name}] " $0; fflush(); }'
          EOF

          chmod 0755 "$out/hermes-${name}/run" "$out/hermes-${name}/log/run"
        '')
        cfg.profiles)}
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: profile: let
        home = profile.homeDirectory;
        envDir = "/run/host-hermes-profiles/${name}/env.d";
        workspaceDirs =
          lib.concatMapStringsSep "\n" (dir: ''
            install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/workspace/${dir}"}
          '')
          profile.workspaceDirectories;
      in
        lib.optionalString profile.dashboard.enable ''
          mkdir -p "$out/hermes-dashboard-${name}/log"

          cat > "$out/hermes-dashboard-${name}/run" <<'EOF'
          #!${pkgs.runtimeShell}
          set -eu
          export PATH=${lib.escapeShellArg path}
          export HERMES_HOME=${lib.escapeShellArg home}
          export HERMES_KANBAN_HOME=/var/lib/hermes
          export CODEX_HOME=${lib.escapeShellArg "${home}/codex"}
          export HOME=${lib.escapeShellArg "${home}/home"}
          export HERMES_DASHBOARD_TUI=1

          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg home}
          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/home"}
          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/codex"}
          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/workspace"}
          install -d -m 0750 -o hermes -g hermes ${lib.escapeShellArg "${home}/logs"}
          ${workspaceDirs}
          install -m 0640 -o hermes -g hermes ${profileConfigFile name profile} ${lib.escapeShellArg "${home}/config.yaml"}

          setup_lock=${lib.escapeShellArg "${home}/.setup.lock"}
          while ! mkdir "$setup_lock" 2>/dev/null; do
            sleep 0.1
          done

          host_tmp="$(mktemp)"
          env_tmp="$(mktemp)"
          trap 'rm -f "$host_tmp" "$env_tmp"; rmdir "$setup_lock"' EXIT

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

          set -a
            . ${lib.escapeShellArg "${home}/.env"}
            set +a

            trap - EXIT
            rm -f "$host_tmp" "$env_tmp"
            rmdir "$setup_lock"

            exec 2>&1
            exec ${runAsHermes} ${lib.getExe hermesPackage} dashboard --host 0.0.0.0 --port ${toString profile.dashboard.port} --no-open --insecure --tui
          EOF

          cat > "$out/hermes-dashboard-${name}/log/run" <<'EOF'
          #!${pkgs.runtimeShell}
          exec ${pkgs.gawk}/bin/awk '{ print "[hermes-dashboard-${name}] " $0; fflush(); }'
          EOF

          chmod 0755 "$out/hermes-dashboard-${name}/run" "$out/hermes-dashboard-${name}/log/run"
        '')
      cfg.profiles)}
    '';

    init = pkgs.writeShellApplication {
      name = "hermes-container-init";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.s6
      ];
      text = ''
        set -eu

        install -d -m 0755 /run/service
        cp -R ${serviceTree}/. /run/service/
        chmod -R u+w /run/service

        exec s6-svscan /run/service
      '';
    };

    image = pkgs.dockerTools.buildLayeredImage {
      name = "hermes-agent";
      tag = "nix";
      contents = [
        hermesPackage
        init
        llmPkgs.codex
        llmPkgs.opencode
        pkgs.bash
        pkgs.bun
        pkgs.cacert
        pkgs.coreutils
        pkgs.curl
        pkgs.duckdb
        pkgs.findutils
        pkgs.gawk
        pkgs.gh
        pkgs.git
        pkgs.gnused
        pkgs.htop
        pkgs.jq
        pkgs.openssh
        pkgs.s6
        pkgs.s6-linux-utils
        pkgs.uv
        pkgs.vim
      ];
      extraCommands = ''
        mkdir -p bin etc tmp var/lib run
        ln -sf ${pkgs.bash}/bin/sh bin/sh
        cat > etc/passwd <<'EOF'
        root:x:0:0:root:/root:/bin/sh
        hermes:x:1000:1000:Hermes:/var/lib/hermes:/bin/sh
        EOF
        cat > etc/group <<'EOF'
        root:x:0:
        hermes:x:1000:
        EOF
        chmod 1777 tmp
      '';
      config = {
        Entrypoint = ["${lib.getExe init}"];
        Env = [
          "HERMES_HOME=/var/lib/hermes"
          "HERMES_KANBAN_HOME=/var/lib/hermes"
          "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          "PATH=${path}"
          "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        ];
        ExposedPorts = lib.listToAttrs (map (port: {
            name = "${toString port}/tcp";
            value = {};
          })
          publishedPorts);
      };
    };

    profilePublishedPorts = lib.concatMap (profile:
      lib.optional profile.apiServer.enable profile.apiServer.port
      ++ [profile.webhook.port])
    (lib.attrValues cfg.profiles);

    dashboardPublishedPorts = lib.concatMap (profile:
      lib.optional profile.dashboard.enable profile.dashboard.port)
    (lib.attrValues cfg.profiles);

    publishedPorts = lib.unique (profilePublishedPorts ++ dashboardPublishedPorts);

    openPorts = lib.unique (lib.concatMap (profile:
        lib.optional (profile.apiServer.enable && profile.apiServer.openFirewall) profile.apiServer.port
        ++ lib.optional profile.webhook.openFirewall profile.webhook.port)
      (lib.attrValues cfg.profiles)
      ++ lib.concatMap (profile:
        lib.optional (profile.dashboard.enable && profile.dashboard.openFirewall) profile.dashboard.port)
      (lib.attrValues cfg.profiles));

    containerVolumes =
      [
        "${cfg.dataDirectory}:/var/lib/hermes:Z"
      ]
      ++ lib.mapAttrsToList (name: profile: "${toString profile.environmentDirectory}:/run/host-hermes-profiles/${name}/env.d:ro,Z")
      cfg.profiles;

    containerPorts = lib.map (port: "${toString port}:${toString port}") publishedPorts;

    dashboardProfile = cfg.profiles.${cfg.dashboard.profile};
    dashboardPort = dashboardProfile.dashboard.port;

    codexProfileCases = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: profile: ''
        ${lib.escapeShellArg name})
          home=${lib.escapeShellArg profile.homeDirectory}
          ;;
      '')
      cfg.profiles);

    podmanExec = "${pkgs.podman}/bin/podman exec -it ${lib.escapeShellArg cfg.containerName}";

    hermesCodexLogin = pkgs.writeShellApplication {
      name = "hermes-codex-login";
      runtimeInputs = [
        pkgs.podman
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
            codex_args="login --device-auth"
            ;;
          status)
            codex_args="login status"
            ;;
          logout)
            codex_args="logout"
            ;;
          *)
            echo "Usage: hermes-codex-login [${lib.concatStringsSep "|" (lib.attrNames cfg.profiles)}] [login|status|logout]" >&2
            exit 2
            ;;
        esac

        exec ${podmanExec} /bin/sh -lc "install -d -m 0750 -o hermes -g hermes '$home/codex' && exec ${runAsHermes} env CODEX_HOME='$home/codex' HOME='$home/home' codex $codex_args"
      '';
    };

    hermesWeb = pkgs.writeShellApplication {
      name = "hermes-web";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.xdg-utils
      ];
      text = ''
        dashboard_url="http://127.0.0.1:${toString dashboardPort}/"
        kanban_url="http://127.0.0.1:${toString dashboardPort}/kanban"

        case "''${1:-print}" in
          print)
            printf 'Hermes dashboard: %s\n' "$dashboard_url"
            printf 'Hermes Kanban:    %s\n' "$kanban_url"
            ;;
          open)
            printf 'Opening Hermes dashboard: %s\n' "$dashboard_url"
            xdg-open "$dashboard_url" >/dev/null 2>&1 &
            ;;
          kanban)
            printf 'Opening Hermes Kanban: %s\n' "$kanban_url"
            xdg-open "$kanban_url" >/dev/null 2>&1 &
            ;;
          all)
            printf 'Opening Hermes dashboard: %s\n' "$dashboard_url"
            printf 'Opening Hermes Kanban:    %s\n' "$kanban_url"
            xdg-open "$dashboard_url" >/dev/null 2>&1 &
            xdg-open "$kanban_url" >/dev/null 2>&1 &
            ;;
          *)
            echo "Usage: hermes-web [print|open|kanban|all]" >&2
            exit 2
            ;;
        esac
      '';
    };

    profileTuiWrappers = lib.mapAttrsToList (name: profile:
      pkgs.writeShellApplication {
        name = "hermes-${name}";
        runtimeInputs = [
          pkgs.podman
        ];
        text = ''
          exec ${podmanExec} /bin/sh -lc "cd '${profile.homeDirectory}/workspace' && exec ${runAsHermes} env HERMES_HOME='${profile.homeDirectory}' HERMES_KANBAN_HOME=/var/lib/hermes CODEX_HOME='${profile.homeDirectory}/codex' HOME='${profile.homeDirectory}/home' hermes --tui"
        '';
      })
    cfg.profiles;
  in {
    assertions = [
      {
        assertion = cfg.profiles != {};
        message = "services.hermesContainer.profiles must define at least one Hermes profile.";
      }
      {
        assertion = !cfg.dashboard.enable || lib.hasAttr cfg.dashboard.profile cfg.profiles;
        message = "services.hermesContainer.dashboard.profile must name an existing Hermes profile.";
      }
    ];

    environment.systemPackages =
      lib.optional cfg.dashboard.enable hermesWeb
      ++ [
        hermesCodexLogin
      ]
      ++ profileTuiWrappers;

    systemd.tmpfiles.rules =
      [
        "d /var/lib/hermes-agent 0755 root root - -"
        "d ${cfg.dataDirectory} 0750 1000 1000 - -"
        "d ${cfg.dataDirectory}/profiles 0750 1000 1000 - -"
      ]
      ++ lib.concatMap (profile: [
        "d ${builtins.dirOf profile.environmentDirectory} 0755 root root - -"
        "d ${profile.environmentDirectory} 0755 root root - -"
      ]) (lib.attrValues cfg.profiles);

    networking.firewall.allowedTCPPorts = openPorts;

    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers.${cfg.containerName} = {
      autoStart = cfg.autostart;
      image = "localhost/hermes-agent:nix";
      imageFile = image;
      ports = containerPorts;
      volumes = containerVolumes;
      extraOptions = [
        "--replace"
        "--pull=never"
      ];
    };
  });
}
