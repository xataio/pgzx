toplevel @ {
  config,
  flake-parts-lib,
  inputs,
  lib,
  ...
}: let
  inherit
    (builtins)
    mapAttrs
    readDir
    ;
  inherit
    (lib)
    filterAttrs
    mkOption
    types
    ;
  inherit
    (flake-parts-lib)
    mkPerSystemOption
    ;

  projectPackagesOverlay = let
    loadPackagesOverlay = final: _prev:
      mapAttrs
      (name: _: final.callPackage (import ../pkgs/${name}) {})
      (filterAttrs (_: v: v == "directory")
        (readDir ../pkgs));
  in
    if builtins.pathExists ../pkgs
    then loadPackagesOverlay
    else (_final: prev: prev);
in {
  imports = [];

  options = let
    nixpkgsOption = mkOption {
      default = {
        config = {};
        overlays = [];
      };

      type = types.submodule {
        options = {
          config = mkOption {
            description = "Configuration to apply to the nixpkgs.";
            type = types.attrs;
            default = {};
          };

          overlays = mkOption {
            description = "Overlays to apply to the nixpkgs.";
            type = types.listOf (types.functionTo (types.functionTo types.attrs));
            default = [];
          };
        };
      };
    };
  in {
    nixpkgs = nixpkgsOption;

    perSystem = mkPerSystemOption ({...}: {
      options = {
        nixpkgs = nixpkgsOption;
      };
    });
  };

  config = {
    perSystem = {
      config,
      system,
      lib,
      pkgs,
      ...
    }: {
      _module.args.pkgs = lib.mkForce (import inputs.nixpkgs {
        inherit system;

        config = lib.recursiveUpdate (toplevel.config.nixpkgs.config or {}) (config.nixpkgs.config or {});

        overlays =
          (toplevel.config.nixpkgs.overlays or [])
          ++ (config.nixpkgs.overlays or [])
          ++ [projectPackagesOverlay];
      });
    };
  };
}
