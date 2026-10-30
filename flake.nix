{
  description = "My NixOS systems, containers, and service configuration";

  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
    ];
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
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
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
    llm-agents,
    ...
  }: let
    lib = nixpkgs.lib;
    forAllSystems = lib.genAttrs ["x86_64-linux"];
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
          inherit llm-agents;
        };
        modules = [
          # Import the WSL module from the flake input (replaces <nixos-wsl/modules>)
          determinate.nixosModules.default
          nixos-wsl.nixosModules.default

          # Shared common configurations (assuming these exist at these paths)
          ./common
          ./common/host-admin.nix
          ./common/nvidia.nix

          # The new abstracted WSL options
          ./wsl/wsl.nix
        ];
      };

      omen = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit llm-agents;
        };
        modules = [
          determinate.nixosModules.default

          ./common
          ./common/host-admin.nix
          ./common/nvidia.nix
          ./common/desktop.nix
          ./omen/configuration.nix
          ./omen/twingate-gw.nix
        ];
      };
    };
  };
}
