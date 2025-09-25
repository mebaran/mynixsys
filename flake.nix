{
  description = "My NixOS WSL Flake Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Matches a stable release; update if needed for 24.11 features
    nixos-wsl.url = "github:nix-community/NixOS-WSL";

    mynixhome.url = "github:mebaran/mynixhome";
    mynixhome.inputs.nixpkgs.follows = "nixpkgs";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
  };

  outputs = {
    self,
    nixpkgs,
    nixos-wsl,
    determinate,
    ...
  }: {
    nixosConfigurations = {
      nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # Import the WSL module from the flake input (replaces <nixos-wsl/modules>)
          nixos-wsl.nixosModules.default

          # Shared common configurations (assuming these exist at these paths)
          ./common
          ./common/nvidia.nix

          # The new abstracted WSL options
          ./wsl/wsl.nix
        ];
      };

      omen-nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          determinate.nixosModules.default
          ./common
          ./common/nvida.nix

          ./omen/configuration.nix
        ];
      };
    };
  };
}
