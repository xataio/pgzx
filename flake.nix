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

  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }:
    inputs.parts.lib.mkFlake {inherit inputs;} {
      debug = true;

      imports = [
        inputs.pre-commit-hooks-nix.flakeModule
        ./nix/modules/nixpkgs.nix
      ];

      flake.overlays = rec {
        default = nixpkgs.lib.composeManyExtensions [
          zigpkgs
          zls
          pgzx_scripts
        ];
        zigpkgs = inputs.zig-overlay.overlays.default;
        zls = _final: prev: {
          zls = inputs.zls.packages.${prev.system}.zls;
        };
        pgzx_scripts = _final: prev: {
          pgzx_scripts = self.packages.${prev.system}.pgzx_scripts;
        };
      };

      flake.templates = rec {
        default = init;
        init = {
          path = ./nix/templates/init;
          description = "Initialize postgres extension projects";
        };
      };

      systems = ["x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin"];

      perSystem = {
        system,
        config,
        lib,
        pkgs,
        ...
      }: {
        nixpkgs = {
          config.allowBroken = true;
          overlays = [
            inputs.zig-overlay.overlays.default
            (_final: _prev: {
              zls = inputs.zls.packages.${system}.zls;
            })
          ];
        };

        pre-commit.pkgs = pkgs;
        pre-commit.settings = {
          hooks = {
            # editorconfig-checker.enable = true;

            # check github actions files
            actionlint.enable = true;

            # check nix files
            alejandra.enable = true;
            deadnix.enable = true;

            # check shell scripts
            shellcheck.enable = true;
            shfmt_local = {
              enable = true;
              name = "shfmt";
              description = "Shell script formatter";
              types = ["shell"];
              entry = "${pkgs.shfmt}/bin/shfmt -d -i 0 -ci -s";
            };

            # zig linters
            zigfmt = {
              enable = true;
              name = "Zig fmt";
              entry = "${pkgs.zigpkgs.master}/bin/zig fmt --check";
              files = "\\.zig$|\\.zon$";
            };
          };
        };

        packages.pgzx_scripts = pkgs.stdenvNoCC.mkDerivation {
          name = "pgzx_scripts";
          src = ./dev/bin;
          installPhase = ''
            mkdir -p $out/bin
            cp -r $src/* $out/bin
          '';
        };

        devShells = let
          devshell_nix = (import ./devshell.nix) {
            inherit pkgs;
            inherit lib;
          };

          user_shell =
            devshell_nix
            // {
              shellHook = ''
                ${devshell_nix.shellHook or ""}
                ${config.pre-commit.devShell.shellHook or ""}
              '';
            };

          mkShell = pkgs.mkShell;

          # On darwin we expect command line tools to be installed.
          # It is possible to install clang/gcc as nix package, but linking
          # can be quite a pain.
          # On non-darwin systems we will use the nix toolchain for now.
          useSystemCC = pkgs.stdenv.isDarwin;
        in {
          default = mkShell user_shell;

          # Create development shell with C tools and dependencies to build Postgres locally.
          debug = mkShell (user_shell
            // {
              hardeningDisable = ["all"];

              packages =
                user_shell.packages
                ++ [
                  pkgs.flex
                  pkgs.bison
                  pkgs.meson
                  pkgs.ninja
                  pkgs.ccache
                  pkgs.pkg-config
                  pkgs.cmake

                  pkgs.icu
                  pkgs.zip
                  pkgs.readline
                  pkgs.openssl
                  pkgs.libxml2
                  pkgs.llvmPackages_17.llvm
                  pkgs.llvmPackages_17.lld
                  pkgs.llvmPackages_17.clang
                  pkgs.llvmPackages_17.clang-unwrapped
                  pkgs.lz4
                  pkgs.zstd
                  pkgs.libxslt
                  pkgs.python3
                ]
                ++ (lib.optionals (!useSystemCC) [
                  pkgs.clang
                ]);
            });
        };
      };
    };
}
