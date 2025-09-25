{
  description = "My NixOS WSL Flake Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Matches a stable release; update if needed for 24.11 features
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    home-manager = {
      url = "github:nix-community/home-manager";
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
    self,
    nixpkgs,
    nixos-wsl,
    determinate,
    home-manager,
    mynixhome,
    ...
  }: {
    nixosConfigurations = {
      wsl = nixpkgs.lib.nixosSystem {
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

      omen = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          determinate.nixosModules.default

          # System modules
          ./common
          ./common/nvidia.nix
          ./omen/configuration.nix

          # Home manager
          home-manager.nixosModules.home-manager

          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            # Import your user's home-manager config from GitHub
            home-manager.users.mebaran = mynixhome.homeConfigurations.mebaran;
          }
        ];
      };
    };
  };
}
