{
  description = "Description for the project";

  # Inputs are the flake references that are used in the flake.
  # Nix will fetch the flake and stores the hash in the flake.lock file.
  inputs = {
    # Nixpkgs provides the many packags that are normally available in NixOS.
    #
    # WARNING:
    # We currently pin the verion to 0.2311.555610 to ensure that the zig build
    # works correctly. Recent updates to nixpkgs did introduce breaking changes to
    # the build environemnt variables, which makes the Zig compiler fail.
    #
    # Issue: https://github.com/ziglang/zig/issues/18998
    # When resolves remove the '=' from the URL to update to the latest stable
    # version of nixpkgs.
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/=0.2311.555610.tar.gz";

    # Flake parts is a library to write flakes in a more modular way similar to
    # NixOS modules.
    parts.url = "github:hercules-ci/flake-parts";

    # pgzx flake provides us with extra tools and a supported version of the Zig compiler.
    # The flake re-exports the zig-overlay and zls flakes.
    pgzx = {
      url = "github:xataio/pgzx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: let
    name = "example";
    version = "0.1";
  in
    inputs.parts.lib.mkFlake {inherit inputs;} {
      # Supported system for which we want to be able to build the project on.
      systems = ["x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin"];

      perSystem = {
        config,
        lib,
        pkgs,
        system,
        ...
      }: {
        # Ensure that 'pkgs' has the dependencies from the pgzx flake available.
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            inputs.pgzx.overlays.default
          ];
          config = {
            # extra configurations
            #allowBroken = true;
            #allowUnfree = true;
          };
        };

        # The projects default package is the package that is built when we run `nix build`
        #
        # The devshell will import the projects build dependencies.
        packages.default = pkgs.stdenvNoCC.mkDerivation {
          pname = name;
          version = version;

          src = ./.;
          nativeBuildInputs = [
            pkgs.zigpkgs.master
            pkgs.pkg-config
          ];

          buildInputs = [
            pkgs.openssl
          ];
        };

        devShells.default = let
          # Load the shell configuration from devshell.nix.
          userShell = (import ./devshell.nix) {
            inherit lib pkgs;

            # Pass the default package as project to the devshell. This
            # allows the devshell to import the project and its dependencies.
            project = config.packages.default;
          };

          mkShell = pkgs.mkShell.override {
            # optionally override the default configuration of the mkShell derivation.
          };
        in
          mkShell (userShell
            // {
              # Optionally override or extend the shell configuration.
              # For example when using the pre-commit-hook module we want to
              # merge the merge the shell hooks of our flake with the
              # pre-commit-hook shellHook to ensure the all dependencies are
              # properly configured when entering the shell.
              shellHook = ''
                ${userShell.shellHook or ""}
              '';
            });
      };
    };
}
