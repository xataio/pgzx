{
  description = "Description for the project";

  inputs = {
    # For now let's use stable nixpkgs. `libxml2` is introducing breaking
    # changes that break postgres compilation
    #
    # nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.0.tar.gz";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2311.554738.tar.gz";

    parts.url = "github:hercules-ci/flake-parts";

    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zls = {
      url = "github:zigtools/zls";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.zig-overlay.follows = "zig-overlay";
    };

    pre-commit-hooks-nix = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.parts.lib.mkFlake {inherit inputs;} {
      debug = true;

      imports = [
        inputs.pre-commit-hooks-nix.flakeModule
        ./nix/modules/nixpkgs.nix
      ];

      nixpkgs = {
        config.allowBroken = true;
        overlays = [
          inputs.zig-overlay.overlays.default
          (_final: prev: {
            zls = inputs.zls.packages.${prev.system}.zls;
          })
        ];
      };

      systems = ["x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin"];

      perSystem = {
        config,
        lib,
        pkgs,
        ...
      }: {
        pre-commit.pkgs = pkgs;
        pre-commit.settings = {
          hooks = {
            # editorconfig-checker.enable = true;
            taplo.enable = true;
            alejandra.enable = true;
            deadnix.enable = true;
            yamllint.enable = true;
          };
        };

        devShells.default = let
          user_shell = (import ./devshell.nix) {
            inherit pkgs;
            inherit lib;
          };
        in
          pkgs.mkShell (user_shell
            // {
              shellHook = ''
                ${user_shell.shellHook or ""}
                ${config.pre-commit.devShell.shellHook or ""}
              '';
            });
      };
    };
}
