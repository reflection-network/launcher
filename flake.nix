{
  description = "Dev launcher — polls git, rebuilds and restarts agent containers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        launcher = pkgs.writeShellApplication {
          name = "launch";
          runtimeInputs = with pkgs; [ git nix docker coreutils ];
          text = builtins.readFile ./launch.sh;
        };
      in {
        packages.default = launcher;
        apps.default = {
          type = "app";
          program = "${launcher}/bin/launch";
        };
      }
    );
}
