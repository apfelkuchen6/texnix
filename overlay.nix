final: prev:
let
  texnix = {
    luametatex = final.callPackage ./pkgs/luametatex { };

    context = final.callPackage ./pkgs/context {
      luatex = final.texnix.texlive.bin.core-big.luatex;
      luametatex = final.texnix.luametatex;
    };

    texlive = final.callPackage ./pkgs/texlive { };
  };
in texnix // { inherit texnix; }
