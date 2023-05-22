{
  description = "Up-to-date nix distribution of TeX typesetting software";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  nixConfig = {
    extra-substituters = [ "https://nix.tex.beauty/texnix" ];
    extra-trusted-public-keys =
      [ "texnix:z8vvh6mMe7RgmStOgIWtu44Lts4GSkURrj2mL59pG6w=" ];
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    {
      overlays = rec {
        texnix = import ./overlay.nix;
        default = texnix;
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = builtins.attrValues self.overlays;
        pkgs = import nixpkgs { inherit system overlays; };
        lib = nixpkgs.lib;
      in {
        legacyPackages = pkgs.texnix;
        checks = lib.filterAttrs (_: lib.isDerivation)
          (pkgs.callPackage ./tests/texlive { });
      });
}
