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

      pkgs.zigpkgs.master
      pkgs.zls
    ];

  shellHook = ''
    export PRJ_ROOT=$PWD
    export PG_HOME=$PRJ_ROOT/workdir/system
    export PATH="$PG_HOME/lib/postgresql/pgxs/src/test/regress:$PATH"
    export PATH="$PG_HOME/bin:$PRJ_ROOT/dev/scripts:$PATH"

    alias root='cd $PRJ_ROOT'

    menu
  '';
}
