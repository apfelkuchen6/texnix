# wrap whole file into an attrset
1i{ # no indentation
$a}

# extract repository metadata
/^name 00texlive\.config$/,/^$/{
  s/^name (.*)$/"\1" = {/p
  /^$/,1i};

  s!^depend frozen/0$!  frozen = false;!p
  s!^depend frozen/1$!  frozen = true;!p
  s!^depend release/(.*)$!  year = \1;!p
  s!^depend revision/(.*)$!  revision = \1;!p
}

# form an attrmap per package
# ignore packages whose name contains "." (such as binaries)
:next-package
/^name ([^.]+|texlive\.infra)$/,/^$/{
  # quote package names, as some start with a number :-/
  s/^name (.*)$/"\1" = {/p

  # extract revision
  s/^revision ([0-9]*)$/  revision = \1;/p

  # extract hashes of *.tar.xz
  s/^containerchecksum (.*)/  sha512.run = "\1";/p
  s/^doccontainerchecksum (.*)/  sha512.doc = "\1";/p
  s/^srccontainerchecksum (.*)/  sha512.source = "\1";/p

  # number of path components to strip, defaulting to 1 ("texmf-dist/")
  /^relocated 1/i\  stripPrefix = 0;

  # extract version and clean unwanted chars from it
  /^catalogue-version/y/ \/~/_--/
  /^catalogue-version/s/[\#,:\(\)]//g
  s/^catalogue-version_(.*)/  version = "\1";/p

  # extract deps
  /^depend [^.]+$/{
    s/^depend (.+)$/  deps = [\n    "\1"/

    # loop through following depend lines
    :next
      h ; N     # save & read next line
      s/\ndepend ([^.]+|texlive\.infra)$/\n    "\1"/
      s/\ndepend (.+)$//
      t next    # loop if the previous lines matched

    x; s/$/\n  ];/p ; x     # print saved deps
    s/^.*\n//   # remove deps, resume processing
  }

  # detect presence of notable files
  /^runfiles /{
    s/^runfiles .*$//  # ignore the first line
    :next-file
      h ; N            # save to hold space & read next line
      s!\n (.+)$! \1!  # save file name
      t next-file      # loop if the previous lines matched

    x                  # work on saved lines in hold space
    / (RELOC|texmf-dist)\//i\  hasRunfiles = true;
    / tlpkg\//i\  hasTlpkg = true;
    x                  # restore pattern space
    s/^.*\n//          # remove saved lines, resume processing
  }

  # extract hyphenation patterns and formats
  # (this may create duplicate lines, use uniq to remove them)
  /^execute\sAddHyphen/i\  hasHyphens = true;

  # extract format details
  /^execute\sAddFormat\s/{
    i\  formats = [
    :next-format

    # create one attribute set per format
    # note that format names are not unique

    # plain keys: name, engine, patterns
    # optionally double quoted key: options
    # boolean key: mode (enabled/disabled)
    # comma-separated lists: fmttriggers, patterns

    s/(^|\n)execute\sAddFormat/    {/
    s/\s+options="([^"]+)"/\n      options = "\1";/
    s/\s+(name|engine|options)=([^ \t\n]+)/\n      \1 = "\2";/g
    s/\s+mode=enabled//
    s/\s+mode=disabled/\n      enabled = false;/
    s/\s+(fmttriggers|patterns)=([^ \t\n]+)/\n      \1 = [ "\2" ];/g
    s/$/\n    }\n/

    :split-triggers
    s/"([^,]+),([^"]+)" ]/"\1" "\2" ]/;
    t split-triggers   # repeat until there are no commas

    # save & read next line
    h ; N
    # continue processing if still matching
    /\nexecute\sAddFormat\s[^\n]*$/b next-format

    x; s/$/  ];/p ; x # print saved formats
    s/^.*\n//         # remove formats, resume processing
  }

  # extract postaction scripts (right now, at most one per package, so a string suffices)
  s/^postaction script file=(.*)$/  postactionScript = "\1";/p

  /^docfiles /,/^[^ ]/{
    s! (texmf-dist|RELOC)/doc/man/.*!  hasManpagesInDoc = true;!p
  }

  /^runfiles /,/^[^ ]/{
    s! (texmf-dist|RELOC)/doc/man/.*!  hasManpagesInRun = true;!p
  }

  # close attrmap
  /^$/{
    i};
    b next-package
  }
}

# add list of binaries from one of the architecture-specific packages
/^name ([^.]+)\.x86_64-linux$/,/^$/{
  s/^name (.*)\.x86_64-linux$/"\1".binfiles = [/p
  s!^ bin/x86_64-linux/(.+)$!  "\1"!p
  /^$/i];
}
