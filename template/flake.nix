{
  description = "example LaTeX project";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    texnix.url = "github:apfelkuchen6/texnix";
    texnix.inputs.nixpkgs.follows = "nixpkgs";
    texnix.inputs.flake-utils.follows = "flake-utils";
  };

  nixConfig = {
    extra-substituters = [ "https://nix.tex.beauty/texnix" ];
    extra-trusted-public-keys =
      [ "texnix:z8vvh6mMe7RgmStOgIWtu44Lts4GSkURrj2mL59pG6w=" ];
  };

  outputs = inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [ inputs.texnix.overlays.texnix ];
        };
      in rec {
        packages.pdf = pkgs.stdenvNoCC.mkDerivation {
          name = "pdfs";
          src = inputs.self;
          nativeBuildInputs = with pkgs;
            [
              (texlive.combine {
                inherit (texlive) scheme-medium blindtext mwe;
              })
            ];
          buildPhase = "HOME=$(mktemp -d) latexmk";
          installPhase = ''
            mkdir -p $out
            cp build/*.pdf $out
          '';
        };
        packages.default = packages.pdf;
        devShells.default = pkgs.mkShell { inputsFrom = [ packages.pdf ]; };
      });
}
