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

  options.mynixsys.unfreeLicenses = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Unfree license short names (e.g. \"CUDA EULA\") allowed by this system.";
  };

  config.nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) config.mynixsys.unfreePackages
    || builtins.any (l: builtins.elem (l.shortName or "") config.mynixsys.unfreeLicenses)
    (lib.toList (pkg.meta.license or []));
}
