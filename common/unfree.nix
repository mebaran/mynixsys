{
  config,
  lib,
  ...
}: {
  options.mynixsys.unfreePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Exact unfree package names allowed by this system.";
  };

  config.nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) config.mynixsys.unfreePackages;
}
