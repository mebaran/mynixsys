{
  description = "My NixOS WSL Flake Configuration";

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

    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
    niri,
    microvm,
    llm-agents,
    ...
  }: let
    forAllSystems = nixpkgs.lib.genAttrs ["x86_64-linux"];
  in {
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    homeConfigurations = mynixhome.homeConfigurations;
    nixosConfigurations = {
      nixos-wsl = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit llm-agents microvm;
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
          inherit llm-agents microvm;
        };
        modules = [
          determinate.nixosModules.default
          niri.nixosModules.niri
          microvm.nixosModules.host

          ./common
          ./common/nvidia.nix
          ./common/desktop.nix
          ./omen/configuration.nix
          ./microvm/openclaw-microvm.nix
        ];
      };
    };
  };
}
