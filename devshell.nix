{
  pkgs,
  lib,
  ...
}: let
  menu = ''

    PGZX development shell
    ======================

    Available commands:
      menu        - show this menu
      pglocal     - Create local installation from existing postgresql installation
      pguse       - Change default local installation to use
      pginit      - Initialize new test database in local installation
      pgstart     - Start local installation
      pgstop      - Stop local installation

    Shell aliases (might not work with direnv):
      root        - cd to project root
  '';

  makeScripts = scripts:
    lib.mapAttrsToList
    (name: script: pkgs.writeShellScriptBin name script)
    scripts;

  scripts = makeScripts {
    menu = ''
      cat <<EOF
      ${menu}
      EOF
    '';
  };
  # On darwin we expect command line tools to be installed.
  # It is possible to install clang/gcc as nix package, but linking
  # can be quite a pain.
  # On non-darwin systems we will use the nix toolchain for now.
  #useSystemCC = pkgs.stdenv.isDarwin;
in {
  packages =
    scripts
    ++ [
      pkgs.pre-commit
      pkgs.alejandra

      pkgs.postgresql_16_jit
      pkgs.openssl
      pkgs.gss
      pkgs.krb5

      pkgs.pkg-config

      pkgs.zigpkgs.master
      pkgs.zls
    ];

  shellHook = ''
    export PRJ_ROOT=$PWD
    export PG_HOME=$PRJ_ROOT/out/default
    export PATH="$PG_HOME/lib/postgresql/pgxs/src/test/regress:$PATH"
    export PATH="$PG_HOME/bin:$PRJ_ROOT/dev/bin:$PATH"

    # Nix postgres is patched to find and install libraries into another directory
    # than the default. For our local setup we must overwrite the default location by using
    # the NIX_PGLIBDIR environment variable.
    export NIX_PGLIBDIR=$PG_HOME/lib

    alias root='cd $PRJ_ROOT'

    menu
  '';
}
