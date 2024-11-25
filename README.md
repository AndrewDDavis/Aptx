# Aptx

Perform Apt and Dpkg operations.

This function facilitates common package management operations. It
automatically invokes sudo when necessary (may request a password).

Usage

  `aptx <cmd> [opts ...] [args ...]`

Commands

   ud : update index and list upgradeable

   in : install package(s)
 inma : install and mark-auto
 inis : install with --install-suggests
 innr : install with --no-install-recommends

   ug : upgrade package(s) (safest, no install or remove)
  nug : upgrade --with-new-pkgs, but explicitly prevents removal. This can also be
        useful when the install command would remove packages and that is undesirable,
        and can be used as 'nug --mark-auto <pkg>' to upgrade a specific package
        without marking it as manually installed.
  fug : full-upgrade (AKA dist-upgrade, may remove packages)
 snug : simulated nug (uses --trivial-only for brief output). For more
        complete simulation output, showing breakages in [...], use
        'nug -s' or 'fug -s'.

    s : search for packages by pattern
  sno : search in pkgs --names-only
 show : show package metadata, install status, conffiles, ...

  lsi : list installed packages (matching a pattern)
  lsm : list --manual-installed packages
  lsu : list --upgradable packages
 lsum : list --upgradable packages, but only those with non-trivial upgrades
  lsh : list packages on hold
 lsrc : list removed packages with residual config
  lsb : list broken packages, requiring reinstall
 lscf : show config files for package(s)

  arm : autoremove package(s)
   ap : autopurge package(s)
  prc : purge removed packages that have residual config (rc)

  hold : hold package (prevents upgrade, removal)
unhold : remove hold on package
 marka : mark package(s) as automatically installed
 markm : mark package(s) as manually installed

rdepi : show installed pkgs that are immediate reverse-deps of a package
  why : recursive rdepi of a package (AKA rdepir)
 iwhy : important recursive rdepi (no suggests, AKA rdepirns)

 hist : view apt's command history

Any arguments provided after the command are passed on to the apt or
dpkg command line. Use the r command to pass command line to apt.

Options

--skb : on upgrades, suppress 'kept back' list (also swallows Y/n prompt)

Useful apt options

  -U : update the index before running install, upgrade, etc.
  -V : show version info for packages to be upgraded (or installed, etc.)
