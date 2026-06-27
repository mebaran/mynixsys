{
  description = "My NixOS systems, containers, and service configuration";

  nixConfig = {
    extra-substituters = ["https://cache.numtide.com"];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Matches a stable release; update if needed for 24.11 features
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # extra flakes for more more modules
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hermes = {
      url = "github:NousResearch/hermes-agent/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager flake from your GitHub repo
    mynixhome = {
      url = "github:mebaran/mynixhome";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = {
    nixpkgs,
    nixos-wsl,
    determinate,
    mynixhome,
    niri,
    llm-agents,
    hermes,
    ...
  }: let
    lib = nixpkgs.lib;
    forAllSystems = lib.genAttrs ["x86_64-linux"];
    mkHermesProfile = name: {
      portOffset,
      homeDirectory ? "/var/lib/hermes/profiles/${name}",
      model ? {
        provider = "openai-codex";
        default = "gpt-5.5";
      },
      fallbackProviders ? [
        {
          provider = "openrouter";
          model = "moonshotai/kimi-k2.6";
        }
      ],
      workspaceDirectories ? [],
    }: {
      environmentDirectory = "/var/lib/hermes-agent/profiles/${name}/env.d";
      inherit homeDirectory;
      inherit model;
      inherit fallbackProviders;
      externalSkillDirectories = [];
      inherit workspaceDirectories;
      apiServer = {
        enable = true;
        host = "0.0.0.0";
        port = 8800 + portOffset;
        openFirewall = true;
      };
      webhook = {
        port = 8900 + portOffset;
        openFirewall = true;
      };
      dashboard = {
        enable = true;
        port = 9000 + portOffset;
        openFirewall = true;
      };
    };
    hermesProfiles = {
      orchestrator = mkHermesProfile "orchestrator" {
        portOffset = 0;
        homeDirectory = "/var/lib/hermes";
        workspaceDirectories = [
          "board"
          "requests"
          "scratch"
        ];
      };
      pa = mkHermesProfile "pa" {
        portOffset = 1;
        workspaceDirectories = [
          "scratch"
          "requests"
        ];
      };
      coder = mkHermesProfile "coder" {
        portOffset = 2;
        workspaceDirectories = [
          "repos"
          "requests"
          "scratch"
        ];
      };
    };
  in {
    formatter = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      pkgs.writeShellApplication {
        name = "alejandra-tree";
        runtimeInputs = [pkgs.alejandra];
        text = ''
          if [ "$#" -eq 0 ]; then
            set -- "''${PRJ_ROOT:-.}"
          fi

          exec alejandra "$@"
        '';
      });

    homeConfigurations = mynixhome.homeConfigurations;
    nixosConfigurations = {
      nixos-wsl = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit hermes llm-agents niri;
        };
        modules = [
          # Import the WSL module from the flake input (replaces <nixos-wsl/modules>)
          determinate.nixosModules.default
          nixos-wsl.nixosModules.default

          # Shared common configurations (assuming these exist at these paths)
          ./common
          ./common/nvidia.nix

          # The new abstracted WSL options
          ./wsl/wsl.nix
        ];
      };

      omen = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit hermes llm-agents niri;
        };
        modules = [
          determinate.nixosModules.default
          niri.nixosModules.niri

          ./common
          ./common/nvidia.nix
          ./common/desktop.nix
          ./omen/configuration.nix
          ./containers/hermes.nix
          {
            services.hermesContainer = {
              enable = true;
              autostart = true;
              podmanUser = "hermes";
              profiles = hermesProfiles;
            };
          }
        ];
      };
    };
  };
}
