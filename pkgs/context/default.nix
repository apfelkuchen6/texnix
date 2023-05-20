{ lib, stdenv, fetchFromGitHub, buildEnv, makeWrapper, libfaketime
, luatex, luametatex
, withUnfree ? false
, extraModules ? [ ] # extra tex directory trees to add to context
}:

let
  version = "unstable-2023-05-08";
  context-distribution = fetchFromGitHub {
    owner = "contextgarden";
    repo = "context";
    rev = "f39019bee22250a40379d621a4f4d2d511bf833f";
    hash = if withUnfree then
      "sha256-+kJtv54Zx+COcRhV5k60jvz5zNnxmrAyUrXMHdsrh/4="
    else
      "sha256-+kJtv54Zx+COcRhV5k60jvz5zNnxmrAyUrXMHdsrh/4=";

    postFetch = lib.optionalString (!withUnfree) ''
      find -name '*koeieletters*' -delete
    '';

    meta = with lib; {
      # license information in https://github.com/contextgarden/context/blob/main/doc/context/documents/general/manuals/mreadme.pdf
      # code: gpl2Plus
      # documentation: cc-by-sa 4.0
      # bundled lm font: GFL (equivalent to lppl13c )
      # bundled koeieletters font: cc-by-nd-25 (unfree!)
      license = with licenses;
        [ gpl2Plus cc-by-sa-40 lppl13c ] ++ lib.optional withUnfree unfree;
      maintainers = with maintainers; [ apfelkuchen6 ];
      description =
        "The runtime files of the ConTeXt typesetting system distribution";
    };
  };

  context-distribution-fonts = fetchFromGitHub {
    owner = "contextgarden";
    repo = "context-distribution-fonts";
    rev = "4c52972dda2da8f36239a7c03577ab3f8cbba9cf";
    hash = "sha256-ckDQR22Cr5LGYSabfszImA8mJEyQlrdKLUnVzop1LP4=";

    meta = with lib; {
      # fontawesome, IBM Plex, Erewhon, KpSans, EB Garamond, Concrete Math, Marvosym, Euler Math, Stix2, Gentium: SIL OFL
      # ALM: Gust Font License with exception: derivatives must change name
      # cc-icons: CC-By-4.0
      # dejavu: free (https://dejavu-fonts.github.io/License.html)
      # wasy2-ps: public domain
      # xcharter: permissive (http://mirrors.ctan.org/fonts/charter/readme.charter)
      # mflogo, manfmt: Knuth License (https://www.ctan.org/license/knuth)
      # XITS: SIL OFL with exception: derivatives must change name
      # Kurier, TeX Gyre, Iwona, Latin Modern, Poltawski: GFL
      # ANTT: GUST Font Nosource License
      license = with licenses; [ ofl lppl13c cc-by-40 free ];
      maintainers = with maintainers; [ apfelkuchen6 ];
      description = "fonts distributed with the ConTeXt distribution";
    };
  };

  texmf-modules = buildEnv {
    name = "context-texmf-modules";
    paths = extraModules;
  };

in stdenv.mkDerivation {
  pname = "context";
  # the ConTeXt distribution generally has no releases.
  # This will remain in unstable-land forever.
  inherit version;

  # no sources, we just symlink the "runtime files" in order to avoid rebuilding everything when adding additional extraModules,
  dontUnpack = true;

  strictDeps = true;

  nativeBuildInputs = [ luametatex luatex makeWrapper libfaketime ];

  dontBuild = true;

  # closely follows the "standard" layout created by the install script of the context distribution
  # the content is organized as follows:
  # share/texmf-context -- the (untouched symlinked) context distribution
  # share/texmf-fonts   -- the (untouched symlinked) fonts for the context distribution
  # share/texmf-modules -- the external content passed via the `extraModules` argument
  # share/texmf-cache   -- inital file system trees and font cache
  # share/texmf         -- binaries, main script and texmfcnf.lua
  installPhase = ''
    runHook preInstall

    export PATH=$out/share/texmf-bin/bin:$PATH

    mkdir -p $out/share
    ln -s ${context-distribution} $out/share/texmf-context

    mkdir -p $out/share/texmf-fonts
    ln -s ${context-distribution-fonts} $out/share/texmf-fonts/fonts

    mkdir -p $out/share/texmf-bin/bin
    cp $(type -P luametatex) $out/share/texmf-bin/bin/luametatex
    cp $(type -P luatex) $out/share/texmf-bin/bin/luatex
    ln -s $out/share/texmf-bin/bin/luametatex $out/share/texmf-bin/bin/context
    ln -s $out/share/texmf-bin/bin/luametatex $out/share/texmf-bin/bin/mtxrun
    ln -s $out/share/texmf-context/scripts/context/lua/{mtxrun,context}.lua $out/share/texmf-bin/bin

    mkdir -p $out/share/texmf/web2c
    # when writing caches, the first writable directory is used. when reading, all are used.
    # So we have the directory in the nix-store (which is populated when building) first, and use ~/.cache/luametatex for runtime write-operations
    sed 's|TEXMFCACHE[[:space:]]*= "$SELFAUTOPARENT/texmf-cache"|TEXMFCACHE = "$SELFAUTOPARENT/texmf-cache:$HOME/.cache/context"|' \
      ${context-distribution}/web2c/contextcnf.lua > $out/share/texmf/web2c/texmfcnf.lua

    ln -s ${texmf-modules} $out/share/texmf-modules

    faketime -f '@1980-01-01 00:00:00' luatex --luaonly $out/share/texmf-bin/bin/mtxrun.lua --generate
    faketime -f '@1980-01-01 00:00:00' luametatex --luaonly $out/share/texmf-bin/bin/mtxrun.lua --generate

    cp -f ${luametatex}/bin/luametatex $out/share/texmf-bin/bin/luametatex
    cp -f ${luatex}/bin/luatex $out/share/texmf-bin/bin/luatex

    makeWrapper $out/share/texmf-bin/bin/luatex $out/bin/luatex --prefix PATH : "$out/share/texmf-bin/bin" --set LUATEXDIR "$out/share/texmf-context/scripts/context/lua"
    makeWrapper $out/share/texmf-bin/bin/luametatex $out/bin/luametatex --prefix PATH : "$out/share/texmf-bin/bin" --set LUATEXDIR "$out/share/texmf-context/scripts/context/lua"
    makeWrapper $out/share/texmf-bin/bin/context $out/bin/context --prefix PATH : "$out/share/texmf-bin/bin" --set LUATEXDIR "$out/share/texmf-context/scripts/context/lua"
    makeWrapper $out/share/texmf-bin/bin/mtxrun $out/bin/mtxrun --prefix PATH : "$out/share/texmf-bin/bin"  --set LUATEXDIR "$out/share/texmf-context/scripts/context/lua"

    runHook postInstall
  '';

  meta = with lib; {
    description = "General-purpose document processor derived from TeX";
    # this "conflicts" with texlive (at least the full and context schemes). When
    # someone adds both texlive and the context distribution to their
    # environment, they almost certainly want to use context from the context
    # distribution.
    priority = -1;
    inherit (context-distribution.meta) license;
    homepage = "https://wiki.contextgarden.net/Main_Page";
    maintainers = with maintainers; [ apfelkuchen6 ];
  };
}
