/* TeX Live user docs
  - source: ../../../../../doc/languages-frameworks/texlive.xml
  - current html: https://nixos.org/nixpkgs/manual/#sec-language-texlive
*/
{ stdenv, lib, fetchurl, runCommand, writeText, buildEnv
, callPackage, ghostscript_headless, harfbuzz
, makeWrapper
, python3, ruby, perl, tk, jdk, bash, snobol4
, gnused, gnugrep, coreutils
, libfaketime, makeFontsConf, asymptote
, useFixedHashes ? true
, recurseIntoAttrs
}:
let
  version = {
    # day of the snapshot being taken
    year = "2023";
    month = "08";
    day = "15";
    # TeX Live version
    texliveYear = 2023;
    # final (historic) release or snapshot
    final = false;
  };

  # The tarballs on CTAN mirrors for the current release are constantly
  # receiving updates, so we can't use those directly. Stable snapshots
  # need to be used instead. Ideally, for the release branches of NixOS we
  # should be switching to the tlnet-final versions
  # (https://tug.org/historic/).
  urlPrefixes = with version; lib.optionals final  [
    # tlnet-final snapshot; used when texlive.tlpdb is frozen
    # the TeX Live yearly freeze typically happens in mid-March
    "https://ftp.tu-chemnitz.de/pub/tug/historic/systems/texlive/${toString texliveYear}/tlnet-final"
    "ftp://tug.org/texlive/historic/${toString texliveYear}/tlnet-final"
  ] ++ [
    # daily snapshots hosted by one of the texlive release managers;
    # used for non-final snapshots and as fallback for final snapshots that have not reached yet the historic mirrors
    # please note that this server is not meant for large scale deployment and should be avoided on release branches
    # https://tug.org/pipermail/tex-live/2019-November/044456.html
    "https://texlive.info/tlnet-archive/${year}/${month}/${day}/tlnet"
  ];

  tlpdbxz = fetchurl {
    urls = map (up: "${up}/tlpkg/texlive.tlpdb.xz") urlPrefixes;
    hash = "sha256-rtCK2Z3FkquVKKJsTDrsCBdLPNjPJbicQm4B/pj9fnE=";
  };

  tlpdbNix = runCommand "tlpdb.nix" {
    inherit tlpdbxz;
    tl2nix = ./tl2nix.sed;
  }
  ''
    xzcat "$tlpdbxz" | sed -rn -f "$tl2nix" | uniq > "$out"
  '';

  # various binaries (compiled)
  bin = callPackage ./bin.nix {
    ghostscript = ghostscript_headless;
    harfbuzz = harfbuzz.override {
      withIcu = true; withGraphite2 = true;
    };
    inherit useFixedHashes;
  };

  # function for creating a working environment from a set of TL packages
  combine = import ./combine.nix {
    inherit bin combinePkgs buildEnv lib makeWrapper writeText runCommand
      stdenv python3 ruby perl gnused gnugrep coreutils libfaketime makeFontsConf bash tl;
    ghostscript = ghostscript_headless;
  };

  tlpdb = import ./tlpdb.nix;

  tlpdbVersion = tlpdb."00texlive.config";

  # the set of TeX Live packages, collections, and schemes; using upstream naming
  tl = let
    # most format -> engine links are generated by texlinks according to fmtutil.cnf at combine time
    # so we remove them from binfiles, and add back the ones texlinks purposefully ignore (e.g. mptopdf)
    removeFormatLinks = lib.mapAttrs (_: attrs:
      if (attrs ? formats && attrs ? binfiles)
      then let formatLinks = lib.catAttrs "name" (lib.filter (f: f.name != f.engine) attrs.formats);
               binNoFormats = lib.subtractLists formatLinks attrs.binfiles;
           in if binNoFormats != [] then attrs // { binfiles = binNoFormats; } else removeAttrs attrs [ "binfiles" ]
      else attrs);

    orig = removeFormatLinks (removeAttrs tlpdb [ "00texlive.config"] );

    overridden = orig // {
      # overrides of texlive.tlpdb

      # only *.po for tlmgr
      texlive-msg-translations = builtins.removeAttrs orig.texlive-msg-translations [ "hasTlpkg" ];

      # TODO we do not build binaries for the following packages (yet!)
      biber-ms = removeAttrs orig.biber-ms [ "binfiles" ];
      xpdfopen = removeAttrs orig.xpdfopen [ "binfiles" ];

      # packages with nonstandard script arrangements

      cluttex = orig.cluttex // {
        binaliases = {
          cllualatex = "cluttex";
          clxelatex = "cluttex";
        };
      };

      context = orig.context // {
        scriptsFolder = "context/lua";
        binaliases = {
          context = bin.luametatex + "/bin/luametatex";
          luametatex = bin.luametatex + "/bin/luametatex";
          mtxrun = bin.luametatex + "/bin/luametatex";
        };
        postFixup =
        # these scripts should not be called explicity,
        # they are read by the engine and MUST NOT be wrapped.
        ''
          chmod -x $out/bin/{mtxrun,context}.lua
        '';
      };

      cslatex = orig.cslatex // {
        # cslatex requires babel to generate its format:
        # texlive-cslatex.formats> ! LaTeX Error: Encoding scheme `IL2' unknown.
        # texlive-cslatex.formats> See the LaTeX manual or LaTeX Companion for explanation.
        # texlive-cslatex.formats> Type  H <return>  for immediate help.
        deps = orig.cslatex.deps ++ [ "babel" ];
      };

      jadetex = orig.jadetex // {
        deps = orig.jadetex.deps ++ [ "etoolbox" ];
      };

      cyrillic-bin = orig.cyrillic-bin // {
        scriptsFolder = "texlive-extra";
      };

      epstopdf = orig.epstopdf // {
        binaliases = {
          repstopdf = "epstopdf";
        };
      };

      fontinst = orig.fontinst // {
        scriptsFolder = "texlive-extra";
      };

      mptopdf = orig.mptopdf // {
        scriptsFolder = "context/perl";
        # mptopdf is a format link, but texlinks intentionally avoids it
        # so we add it back to binfiles to generate it from mkPkgBin
        binfiles = (orig.mptopdf.binfiles or []) ++ [ "mptopdf" ];
      };

      pedigree-perl = orig.pedigree-perl // {
        postFixup = ''
          sed -e '1{ /perl$/!q1 ; s|perl$|perl -I '"$run"'/scripts/pedigree-perl| } ' -i "$out"/bin/*
        '';
      };

      pdfcrop = orig.pdfcrop // {
        binaliases = {
          rpdfcrop = "pdfcrop";
        };
      };

      pdftex = orig.pdftex // {
        scriptsFolder = "simpdftex";
      };

      ptex = orig.ptex // {
        binaliases = {
          pdvitomp = bin.metapost + "/bin/pdvitomp";
          pmpost = bin.metapost + "/bin/pmpost";
          r-pmpost = bin.metapost + "/bin/r-pmpost";
        };
      };

      texdef = orig.texdef // {
        binaliases = {
          latexdef = "texdef";
        };
      };

      texlive-scripts = orig.texlive-scripts // {
        scriptsFolder = "texlive";
        # mktexlsr is distributed by texlive.infra which we exclude from tlpdb.nix
        # man should of course be ignored
        binfiles = (lib.remove "man" orig.texlive-scripts.binfiles) ++ [ "mktexlsr" ];
        binaliases = {
          mktexfmt = "fmtutil";
          texhash = "mktexlsr";
        };
        # fmtutil, updmap need modified perl @INC, including bin.core for TeXLive::TLUtils
        postFixup = ''
          sed -e '1{ /perl$/!q1 ; s|perl$|perl -I '"$run"'/scripts/texlive -I ${bin.core}/share/texmf-dist/scripts/texlive| } ' -i "$out"/bin/fmtutil "$out"/bin/updmap
        '';
      };

      texlive-scripts-extra = orig.texlive-scripts-extra // lib.optionalAttrs
      (lib.all (e: lib.elem e orig.texlive-scripts-extra.binfiles) [ "allec" "kpsepath" "kpsexpand" ])
      {
        scriptsFolder = "texlive-extra";
        binaliases = {
          allec = "allcm";
          kpsepath = "kpsetool";
          kpsexpand = "kpsetool";
        };
        # Patch texlinks.sh back to 2015 version;
        # otherwise some bin/ links break, e.g. xe(la)tex.
        postFixup = ''
          patch --verbose -R "$out"/bin/texlinks < '${./texlinks.diff}'
        '';
      };

      uptex = orig.uptex // {
        binaliases = {
          r-upmpost = bin.metapost + "/bin/r-upmpost";
          updvitomp = bin.metapost + "/bin/updvitomp";
          upmpost = bin.metapost + "/bin/upmpost";
        };
      };

      upmendex = orig.upmendex // {
        # upmendex is "TODO" in bin.nix
        # metapost binaries are in bin.metapost instead of bin.core
        binfiles = lib.remove "upmendex" orig.uptex.binfiles;
        binaliases = {
          r-upmpost = bin.metapost + "/bin/r-upmpost";
          updvitomp = bin.metapost + "/bin/updvitomp";
          upmpost = bin.metapost + "/bin/upmpost";
        };
      };

      # xindy is broken on some platforms unfortunately
      xindy = if (bin ? xindy)
        then orig.xindy // lib.optionalAttrs
        (lib.all (e: lib.elem e orig.xindy.binfiles) [ "xindy.mem" "xindy.run" ])
        {
          # we don't have xindy.run (we use the regular clisp somewhere in the nix store instead)
          # and xindy.mem is in lib/ (where it arguably belongs)
          binfiles = lib.subtractLists [ "xindy.mem" "xindy.run" ] orig.xindy.binfiles;
        }
        else removeAttrs orig.xindy [ "binfiles" ];

      xetex = orig.xetex // lib.optionalAttrs
      (lib.elem "teckit_compile" orig.xetex.binfiles)
      {
        scriptsFolder = "texlive-extra";
        # teckit_compile seems to be missing from bin.core{,-big}
        # TODO find it!
        binfiles = lib.remove "teckit_compile" orig.xetex.binfiles;
      };

      xdvi = orig.xdvi // { # it seems to need it to transform fonts
        deps = (orig.xdvi.deps or []) ++  [ "metafont" ];
      };

      # remove dependency-heavy packages from the basic collections
      collection-basic = orig.collection-basic // {
        deps = lib.filter (n: n != "metafont" && n != "xdvi") orig.collection-basic.deps;
      };
      # add them elsewhere so that collections cover all packages
      collection-metapost = orig.collection-metapost // {
        deps = orig.collection-metapost.deps ++ [ "metafont" ];
      };
      collection-plaingeneric = orig.collection-plaingeneric // {
        deps = orig.collection-plaingeneric.deps ++ [ "xdvi" ];
      };

      texdoc = orig.texdoc // {
        extraRevision = ".tlpdb${toString tlpdbVersion.revision}";
        extraVersion = "-tlpdb-${toString tlpdbVersion.revision}";

        # build Data.tlpdb.lua (part of the 'tlType == "run"' package)
        postUnpack = ''
          if [[ -f "$out"/scripts/texdoc/texdoc.tlu ]]; then
            unxz --stdout "${tlpdbxz}" > texlive.tlpdb

            # create dummy doc file to ensure that texdoc does not return an error
            mkdir -p support/texdoc
            touch support/texdoc/NEWS

            TEXMFCNF="${bin.core}"/share/texmf-dist/web2c TEXMF="$out" TEXDOCS=. TEXMFVAR=. \
              "${bin.luatex}"/bin/texlua "$out"/scripts/texdoc/texdoc.tlu \
              -c texlive_tlpdb=texlive.tlpdb -lM texdoc

            cp texdoc/cache-tlpdb.lua "$out"/scripts/texdoc/Data.tlpdb.lua
          fi
        '';
      };

      # tlshell is a GUI for tlmgr, which cannot be used in the Nix store
      tlshell = removeAttrs orig.tlshell [ "binfiles" "hasRunfiles" ];

      "texlive.infra" = orig."texlive.infra" // {
        scriptsFolder = "texlive";
        deps = [ "texlive-tlpdb" ];

        # these aren't in tlpdb, so we add them manually
        binfiles = [ "tlmgrgui"  "tlmgr" ];
        binAliases = {
          tlmgrgui = "tlmgrgui.pl";
          tlmgr = "tlmgr.pl";
        };

        postFixup = ''
          substituteInPlace $out/bin/tlmgr --replace 'if (-r "$bindir/$kpsewhichname")' 'if (1)'
        '';
      };
    }; # overrides

    in lib.mapAttrs mkTLPkg overridden // {
      texlive-tlpdb.pkgs = [
        (runCommand "texlive-tlpdb" {
          inherit tlpdbxz;
        }
        ''
          mkdir $out
          xzcat "$tlpdbxz" > "$out/texlive.tlpdb"
        '' // {
          tlType = "tlpkg";
          pname = "texlive-tlpdb";
          inherit (tlpdb."00texlive.config") revision;
        })
      ];
    };

  # create a TeX package: an attribute set { pkgs = [ ... ]; ... } where pkgs is a list of derivations
  mkTLPkg = pname: attrs:
    let
      version = attrs.version or (toString attrs.revision);
      mkPkgV = tlType: let
        pkg = attrs // {
          sha512 = attrs.sha512.${if tlType == "tlpkg" then "run" else tlType};
          inherit pname tlType version;
        } // lib.optionalAttrs (tlType == "doc" && attrs.hasManpagesInDoc or false) {
          hasManpages = true;
        } // lib.optionalAttrs (tlType == "run" && attrs.hasManpagesInRun or false) {
          hasManpages = true;
        };
        in mkPkg pkg;
      # tarball of a collection/scheme itself only contains a tlobj file
      # likewise for most packages compiled in bin.core, bin.core-big
      # the fake derivations are used for filtering of hyphenation patterns and formats
      run = if (attrs.hasRunfiles or false) then mkPkgV "run"
          else ({
            inherit pname version;
            tlType = "run";
            hasHyphens = attrs.hasHyphens or false;
            tlDeps = map (n: tl.${n}) (attrs.deps or []);
          } // lib.optionalAttrs (attrs ? formats) { inherit (attrs) formats; });
    in {
      # TL pkg contains lists of packages: runtime files, docs, sources, binaries, formats
      pkgs = let
        pkgs' = [ run ] ++ lib.optional (attrs.sha512 ? doc) (mkPkgV "doc")
          ++ lib.optional (attrs.sha512 ? source) (mkPkgV "source")
          ++ lib.optional (attrs.hasTlpkg or false) (mkPkgV "tlpkg")
          ++ lib.optional (attrs ? binfiles) (mkPkgBin pname version run attrs);
      in pkgs' ++ lib.optional (attrs ? formats)
      (mkPkgFormats pname version pkgs' attrs);
    };

  # map: name -> fixed-output hash
  fixedHashes = lib.optionalAttrs useFixedHashes (import ./fixed-hashes.nix);

  # NOTE: the fixed naming scheme must match generated-fixed-hashes.nix
  # name for the URL
  mkURLName = { pname, tlType, ... }: pname + lib.optionalString (!builtins.elem tlType [ "tlpkg" "run" ]) ".${tlType}";
  # name + revision for the fixed output hashes
  mkFixedName = { tlType, revision, extraRevision ? "", ... }@attrs:
    mkURLName attrs
      + lib.optionalString (tlType == "tlpkg") ".tlpkg"
      + ".r${toString revision}${extraRevision}";
  # name + version for the derivation
  mkTLName = { tlType, version, extraVersion ? "", ... }@attrs:
    mkURLName attrs
      + lib.optionalString (tlType == "tlpkg") ".tlpkg"
      + "-${version}${extraVersion}";

  # build tlType == "bin" containers based on `binfiles` in TLPDB
  # see UPGRADING.md for how to keep the list of shebangs up to date
  # TODO: add extraBuildInputs (?) for adding PATH entries to texlive.combine wrappers
  mkPkgBin = pname: version: run:
  { binfiles, scriptsFolder ? pname, postFixup ? "", binaliases ? {}, ... }@args:
    let binNoAliases = assert (lib.all (e: lib.elem e binfiles) (lib.attrNames binaliases));
          lib.subtractLists (lib.attrNames binaliases) binfiles;
    in
    runCommand "texlive-${pname}.bin-${version}"
      ( {
          # metadata for texlive.combine
          passthru = {
            inherit pname version;
            tlType = "bin";
          };
          # shebang interpreters
          buildInputs = [ bash perl python3 bin.luatex ruby tk snobol4 ];
          run = run.outPath or "";
          inherit scriptsFolder;
        }
      )
      # look for scripts
      # the explicit list of extensions avoid non-scripts such as $binname.cmd, $binname.jar, $binname.pm
      # the order is relevant: $binname.sh is preferred to other $binname.*
      (''
        enable -f '${bash}/lib/bash/realpath' realpath
        mkdir -p "$out/bin"
        for binname in "${builtins.concatStringsSep "\" \"" binNoAliases}" ; do
          target="$out/bin/$binname"

          for bin in '${bin.core}'/bin/"$binname" ${lib.optionalString (bin ? ${pname}) ("'" + bin.${pname}.outPath + "'/bin/\"$binname\"")}; do
            if [[ -e "$bin" && -x "$bin" ]] ; then
              ln -s "$bin" "$target"
              continue 2
            fi
          done

          if [[ -n "$run" ]] ; then
            for script in "$run/scripts/$scriptsFolder/$binname"{,.sh,.lua,.pl,.py,.rb,.sno,.tcl,.texlua,.tlu}; do
              if [[ -e "$script" ]] ; then
                sed -e '1s|^eval '"'"'(exit \$?0)'"'"' && eval '"'"'exec perl -S .*$|#!${perl}/bin/perl|' \
                    -e 's|exec java |exec ${jdk}/bin/java |g' \
                    -e 's|exec perl |exec ${perl}/bin/perl |g' \
                    "$script" > "$target"
                chmod +x "$target"
                continue 2
              fi
            done
          fi
          echo "Error: could not find source for 'bin/$binname'" >&2
          exit 1
        done

        patchShebangs "$out/bin"
      '' +
      # generate aliases
      # we canonicalise the source to avoid symlink chains, and to check that it exists
      ''
        cd "$out"/bin
      '' +
      (lib.concatStrings (lib.mapAttrsToList (alias: source: ''
        ln -s "''$(realpath '${source}')" "$out"/bin/'${alias}'
      '') binaliases))
      + postFixup);

  mkPkgFormats = pname: version: pkgs:
    { formats, deps, ... }@args:
    runCommand "texlive-${pname}.formats-${version}" {
      # metadata for texlive.combine
      passthru = {
        inherit pname version;
        tlType = "fmt";
        inherit formats;
      };
      nativeBuildInputs = [
        libfaketime
        (combine ({
          pkgFilter = pkg:
            pkg.tlType == "run" || pkg.tlType == "bin" || pkg.pname == "core";
          "${pname}" = { inherit pkgs; };
        } // (lib.genAttrs
          ([ "texlive-scripts" "kpathsea" ] ++ deps ++ lib.catAttrs "engine" formats)
          (pkg: tl."${pkg}" or { pkgs = [ ]; }))))
      ];
    } (lib.concatStringsSep "\n" (map (fmt:
      with fmt;
      let
        ismetafont = lib.elem engine [ "mf-nowin" "mflua-nowin" ];
        fmtdir = if ismetafont then "metafont" else engine;
        extension = if ismetafont then "base" else "fmt";
      in ''
        mkdir -p $out/web2c/${engine};
        faketime -f "@1980-01-01 00:00:00 x0.001" \
          ${engine} -ini ${lib.escapeShellArgs (lib.splitString " " options)}
        mv *.${extension} $out/web2c/${engine}/${name}.${extension}
      '') formats));

  # create a derivation that contains an unpacked upstream TL package
  mkPkg = { pname, tlType, revision, version, sha512, extraRevision ? "", postUnpack ? "", stripPrefix ? 1, ... }@args:
    let
      # the basename used by upstream (without ".tar.xz" suffix)
      urlName = mkURLName args;
      tlName = mkTLName args;
      fixedHash = fixedHashes.${mkFixedName args} or null; # be graceful about missing hashes

      urls = args.urls or (if args ? url then [ args.url ] else
        map (up: "${up}/archive/${urlName}.r${toString revision}.tar.xz") (args.urlPrefixes or urlPrefixes));

    in runCommand "texlive-${tlName}"
      ( {
          src = fetchurl { inherit urls sha512; };
          inherit stripPrefix tlType;
          # metadata for texlive.combine
          passthru = {
            inherit pname tlType revision version extraRevision;
          } // lib.optionalAttrs (tlType == "run" && args ? deps) {
            tlDeps = map (n: tl.${n}) args.deps;
          } // lib.optionalAttrs (tlType == "run") {
            hasHyphens = args.hasHyphens or false;
          } // lib.optionalAttrs (tlType == "tlpkg" && args ? postactionScript) {
            postactionScript = args.postactionScript;
          } // lib.optionalAttrs (args ? hasManpages) {
            inherit (args) hasManpages;
          };
        } // lib.optionalAttrs (fixedHash != null) {
          outputHash = fixedHash;
          outputHashAlgo = "sha256";
          outputHashMode = "recursive";
        }
      )
      ( ''
          mkdir "$out"
          if [[ "$tlType"  == "tlpkg" ]]; then
            tar -xf "$src" \
              --strip-components=1 \
              -C "$out" --anchored --exclude=tlpkg/tlpobj --exclude=tlpkg/gpg --keep-old-files \
              tlpkg
          else
            tar -xf "$src" \
              --strip-components="$stripPrefix" \
              -C "$out" --anchored --exclude=tlpkg --keep-old-files
          fi
        '' + postUnpack
      );

  # combine a set of TL packages into a single TL meta-package
  combinePkgs = pkgList: lib.catAttrs "pkg" (
    let
      # a TeX package is an attribute set { pkgs = [ ... ]; ... } where pkgs is a list of derivations
      # the derivations make up the TeX package and optionally (for backward compatibility) its dependencies
      tlPkgToSets = { pkgs, ... }: map ({ tlType, version ? "", outputName ? "", ... }@pkg: {
          # outputName required to distinguish among bin.core-big outputs
          key = "${pkg.pname or pkg.name}.${tlType}-${version}-${outputName}";
          inherit pkg;
        }) pkgs;
      pkgListToSets = lib.concatMap tlPkgToSets; in
    builtins.genericClosure {
      startSet = pkgListToSets pkgList;
      operator = { pkg, ... }: pkgListToSets (pkg.tlDeps or []);
    });

  assertions = with lib;
    assertMsg (tlpdbVersion.year == version.texliveYear) "TeX Live year in texlive does not match tlpdb.nix, refusing to evaluate" &&
    assertMsg (tlpdbVersion.frozen == version.final) "TeX Live final status in texlive does not match tlpdb.nix, refusing to evaluate" &&
    (let all = concatLists (catAttrs "pkgs" (attrValues tl));
         fods = filter (p: isDerivation p && p.tlType != "bin") all;
     in assertMsg (useFixedHashes || builtins.all (p: p ? outputHash) fods)
        "Some TeX Live fixed output hashes are missing. Please read UPGRADING.md on how to build a new 'fixed-hashes.nix'.");

in
  tl // {

    tlpdb = {
      # nested in an attribute set to prevent them from appearing in search
      nix = tlpdbNix;
      xz = tlpdbxz;
    };

    bin = assert assertions; bin;
    combine = assert assertions; combine;

    # Pre-defined combined packages for TeX Live schemes,
    # to make nix-env usage more comfortable and build selected on Hydra.
    combined = with lib; recurseIntoAttrs (
      mapAttrs
        (pname: attrs:
          addMetaAttrs rec {
            description = "TeX Live environment for ${pname}";
            platforms = lib.platforms.all;
            maintainers = with lib.maintainers;  [ veprbl ];
          }
          (combine {
            ${pname} = attrs;
            extraName = "combined" + lib.removePrefix "scheme" pname;
            extraVersion = with version; if final then "-final" else ".${year}${month}${day}";
          })
        )
        { inherit (tl)
            scheme-basic scheme-context scheme-full scheme-gust scheme-infraonly
            scheme-medium scheme-minimal scheme-small scheme-tetex;
        }
    );
  }
