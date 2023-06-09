{ lib, runCommand, fetchurl, file, texlive, writeShellScript }:

{

  # tlpdb-nix = runCommand "texlive-test-tlpdb-nix" {
  #   nixpkgsTlpdbNix = ../../tools/typesetting/tex/texlive/tlpdb.nix;
  #   tlpdbNix = texlive.tlpdb-nix;
  # }
  # ''
  #   mkdir -p "$out"
  #   diff -u "''${nixpkgsTlpdbNix}" "''${tlpdbNix}" | tee "$out/tlpdb.nix.patch"
  # '';

  luaotfload-fonts = runCommand "texlive-test-lualatex" {
    nativeBuildInputs = [
      (with texlive; combine { inherit scheme-medium libertinus-fonts; })
    ];
    input = builtins.toFile "lualatex-testfile.tex" ''
      \documentclass{article}
      \usepackage{fontspec}
      \setmainfont{Libertinus Serif}
      \begin{document}
        \LaTeX{} is great
      \end{document}
    '';
  }
  ''
    export HOME="$(mktemp -d)"
    lualatex -halt-on-error "$input"
    echo success > $out
  '';

  chktex = runCommand "texlive-test-chktex" {
    nativeBuildInputs = [
      (with texlive; combine { inherit scheme-infraonly chktex; })
    ];
    input = builtins.toFile "chktex-sample.tex" ''
      \documentclass{article}
      \begin{document}
        \LaTeX is great
      \end{document}
    '';
  } ''
    # chktex is supposed to return 2 when it (successfully) finds warnings, but no errors,
    # see http://git.savannah.nongnu.org/cgit/chktex.git/commit/?id=ec0fb9b58f02a62ff0bfec98b997208e9d7a5998
    (set +e; chktex -v -nall -w1 "$input" 2>&1; [ $? = 2 ] || exit 1; set -e)  | tee "$out"
    # also check that the output does indeed contain "One warning printed"
    grep "One warning printed" "$out"
  '';

  # https://github.com/NixOS/nixpkgs/issues/75605
  dvipng-basic = runCommand "texlive-test-dvipng-basic" {
    nativeBuildInputs = [ file texlive.combined.scheme-medium ];
    input = fetchurl {
      name = "test_dvipng.tex";
      url = "http://git.savannah.nongnu.org/cgit/dvipng.git/plain/test_dvipng.tex?id=b872753590a18605260078f56cbd6f28d39dc035";
      sha256 = "1pjpf1jvwj2pv5crzdgcrzvbmn7kfmgxa39pcvskl4pa0c9hl88n";
    };
  } ''
    cp "$input" ./document.tex

    latex document.tex
    dvipng -T tight -strict -picky document.dvi
    for f in document*.png; do
      file "$f" | tee output
      grep PNG output
    done

    mkdir "$out"
    mv document*.png "$out"/
  '';

  # test dvipng's limited capability to render postscript specials via GS
  dvipng-ghostscript = runCommand "texlive-test-ghostscript" {
    nativeBuildInputs = [ file (with texlive; combine { inherit scheme-small dvipng; }) ];
    input = builtins.toFile "postscript-sample.tex" ''
      \documentclass{minimal}
      \begin{document}
        Ni
        \special{ps:
          newpath
          0 0 moveto
          7 7 rlineto
          0 7 moveto
          7 -7 rlineto
          stroke
          showpage
        }
      \end{document}
    '';
    gs_trap = writeShellScript "gs_trap.sh" ''
      exit 1
    '';
  } ''
    cp "$gs_trap" ./gs
    export PATH=$PWD:$PATH
    # check that the trap works
    gs && exit 1

    cp "$input" ./document.tex

    latex document.tex
    dvipng -T 1in,1in -strict -picky document.dvi
    for f in document*.png; do
      file "$f" | tee output
      grep PNG output
    done

    mkdir "$out"
    mv document*.png "$out"/
  '';

  # https://github.com/NixOS/nixpkgs/issues/75070
  dvisvgm = runCommand "texlive-test-dvisvgm" {
    nativeBuildInputs = [ file texlive.combined.scheme-medium ];
    input = builtins.toFile "dvisvgm-sample.tex" ''
      \documentclass{article}
      \begin{document}
        mwe
      \end{document}
    '';
  } ''
    cp "$input" ./document.tex

    latex document.tex
    dvisvgm document.dvi -n -o document_dvi.svg
    cat document_dvi.svg
    file document_dvi.svg | grep SVG

    pdflatex document.tex
    dvisvgm -P document.pdf -n -o document_pdf.svg
    cat document_pdf.svg
    file document_pdf.svg | grep SVG

    mkdir "$out"
    mv document*.svg "$out"/
  '';

  texdoc = runCommand "texlive-test-texdoc" {
    nativeBuildInputs = [
      (with texlive; combine {
        inherit scheme-infraonly luatex texdoc;
        pkgFilter = pkg: lib.elem pkg.tlType [ "run" "bin" "doc" ];
      })
    ];
  } ''
    texdoc --version

    texdoc --debug --list texdoc | tee "$out"
    grep texdoc.pdf "$out"
  '';

  # test that language files are generated as expected
  hyphen-base = runCommand "texlive-test-hyphen-base" {
    hyphenBase = lib.head texlive.hyphen-base.pkgs;
    schemeFull = texlive.combined.scheme-full;
    schemeInfraOnly = texlive.combined.scheme-infraonly;
  } ''
    mkdir -p "$out"/{scheme-infraonly,scheme-full}

    # create language files with no hyphenation patterns
    cat "$hyphenBase"/tex/generic/config/language.us >language.dat
    cat "$hyphenBase"/tex/generic/config/language.us.def >language.def
    cat "$hyphenBase"/tex/generic/config/language.us.lua >language.dat.lua

    cat >>language.dat.lua <<EOF
    }
    EOF

    cat >>language.def <<EOF
    %%% No changes may be made beyond this point.

    \uselanguage {USenglish}             %%% This MUST be the last line of the file.
    EOF

    for fname in language.{dat,def,dat.lua} ; do
      diff --ignore-matching-lines='^\(%\|--\) Generated by ' -u \
        {"$hyphenBase","$schemeFull"/share/texmf-var}/tex/generic/config/"$fname" \
        | tee "$out/scheme-full/$fname.patch"
      diff --ignore-matching-lines='^\(%\|--\) Generated by ' -u \
        {,"$schemeInfraOnly"/share/texmf-var/tex/generic/config/}"$fname" \
        | tee "$out/scheme-infraonly/$fname.patch"
    done
  '';

  # test that fmtutil.cnf is fully regenerated on scheme-full
  fmtutilCnf = runCommand "texlive-test-fmtutil.cnf" {
    kpathsea = lib.head texlive.kpathsea.pkgs;
    schemeFull = texlive.combined.scheme-full;
  } ''
    mkdir -p "$out"

    diff --ignore-matching-lines='^# Generated by ' -u \
      {"$kpathsea","$schemeFull"/share/texmf-var}/web2c/fmtutil.cnf \
      | tee "$out/fmtutil.cnf.patch"
  '';

  # verify that the restricted mode gets enabled when
  # needed (detected by checking if it disallows --gscmd)
  rpdfcrop = runCommand "texlive-test-rpdfcrop" {
    nativeBuildInputs = [ (texlive.combine { inherit (texlive) scheme-infraonly pdfcrop; }) ];
  } ''
    ! (pdfcrop --gscmd echo $(command -v pdfcrop) 2>&1 || true) | grep 'restricted mode' >/dev/null
    (rpdfcrop --gscmd echo $(command -v pdfcrop) 2>&1 || true) | grep 'restricted mode' >/dev/null
    mkdir "$out"
  '';

  # check that we have (wrappers for) all scripts listed in TeX Live
  # except for the *-sys scripts, tlmgr, tlshell that cannot operate on the readonly nix store
  # TODO htcopy, htmove, citeproc are *not* distributed by TeX Live and must be removed from scripts.lst
  scriptsLst = runCommand "texlive-test-scripts.lst"
    {
      schemeFull = texlive.combined.scheme-full;
    }
    ''
      source '${texlive.bin.core}/share/texmf-dist/scripts/texlive/scripts.lst'
      for s in $texmf_scripts; do
        tNameExt="''${s##*/}"    # basename
        tName="''${tNameExt%.*}" # remove extension
        [[ "$tName" != *-sys && "$tName" != tlmgr && "$tName" != tlshell ]] || continue
        [[ "$tName" != htcopy && "$tName" != htmove && "$tName" != citeproc ]] || continue
        [[ ! -e "$schemeFull/bin/$tName" && ! -e "$schemeFull/bin/$tNameExt" ]] || continue
        echo "error: wrapper '$tName' for '$s' not found"
        exit 1
      done
      mkdir "$out"
    '';

  # check that all scripts have a Nix shebang
  shebangs = let
      allPackages = with lib; concatLists (catAttrs "pkgs" (filter isAttrs (attrValues texlive)));
      binPackages = lib.filter (p: p.tlType == "bin") allPackages;
    in
    runCommand "texlive-test-shebangs" { }
      (''
        storePath="''${out%/*}"
        echo "checking that all texlive scripts shebangs are in '$storePath'"
        declare -i scriptCount=0 invalidCount=0
      '' +
      (lib.concatMapStrings
        (pkg: ''
          for bin in '${pkg.outPath}'/bin/* ; do
            [[ -x $bin ]] || continue # ignore non-executables in $out/bin
            grep -I -q . "$bin" || continue  # ignore binary files
            scriptCount=$((scriptCount + 1))
            read -r cmdline < "$bin"
            read -r interp <<< "$cmdline"
            if [[ "$interp" != "#!$storePath"/* && "$interp" != "#! $storePath"/* ]] ; then
              echo "error: non-nix shebang '#!$interp' in script '$bin'"
              invalidCount=$((invalidCount + 1))
            fi
          done
        '')
        binPackages)
      + ''
        echo "checked $scriptCount scripts, found $invalidCount non-nix shebangs"
        [[ $invalidCount -gt 0 ]] && exit 1
        mkdir -p "$out"
      ''
      );
}
