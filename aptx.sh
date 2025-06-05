# APT package manager

# TODO
# - readme formatting
# - when running a sno search with a fair number of outputs, aptx takes too long to produce the output, e.g. `aptx sno texlive`
# - in the "why" item, check for manual installed and bold them
# - introduce more apt prefs and sources like [this](https://www.reddit.com/r/debian/comments/1cdkax2/comment/l1crknz/)
# - add a --dry-run (-n or -s) that prints the command and exits
# - add to hist features:
#     + parse dpkg log /var/log/dpkg.log, grep for ' x ' where x is install, upgrade,
#       remove, etc.
#     + get the ability to roll back an upgrade operation by using e.g.:
#       awk '$1 == "2018-09-07" && $3 == "upgrade" {print $4"="$5}' /var/log/dpkg.log > /tmp/rollback_pkgs.txt
#       apt-get -s install $( < rollback_pkgs.txt )
# - when doing aptx lsu, add a --hide-binary-only option, to filter for not showing updates that are only a recompile without changing the software version, e.g.:
#   file (1:5.45-3 => 1:5.45-3+b1)
#   flex (2.6.4-8.2+b2 => 2.6.4-8.2+b3)
# - maybe even have a --major-only option, to filter out updates in the 3rd digit, like 2.6.4 => 2.6.5

# dependencies
import_func physpath \
    || return

aptx() (

    : """Perform Apt and Dpkg operations

    This function facilitates common package management operations. It
    automatically invokes sudo when necessary (may request a password).

    Usage

      aptx <cmd> [opts ...] [args ...]

    Commands

       ud : update index and list upgradeable

       in : install package(s)
     inma : install and mark-auto
     inis : install with --install-suggests
     innr : install with --no-install-recommends

       ug : upgrade package(s) (safest, no install or remove)
      nug : upgrade --with-new-pkgs, but explicitly prevents removal. This is a safe
            option between ug and fug. It is expecially useful when the install or
            full-upgrade commands would remove packages that are needed. It can be used
            as 'nug --mark-auto <pkg>' to upgrade a specific package without marking it
            as manually installed.
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
       cc : run clean and autoclean, to remove all downloaded package files

        hold : hold package (prevents upgrade, removal)
      unhold : remove hold on package
    markauto : mark package(s) as automatically installed
     markman : mark package(s) as manually installed

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
    """

    [[ $# -eq 0  || $1 == @(-h|--help) ]] \
        && { docsh -DT; return; }

    # return on error
    trap 'trap-err $?; return'  ERR
    trap 'trap - ERR RETURN'    RETURN

    # check for apt
    [[ -n $( command -v apt ) ]] \
        || { err_msg 9 "apt not found"; return; }

    # Prepend sudo when not root
    # - also echo the command line using set -x
    run_priv() {

        if [[ $(id -u) -eq 0 ]]
        then
            (
                set -x
                "$@"
            )
        else
            (
                set -x
                sudo "$@"
            )
        fi
    }

    # boldify or dimify with e.g. "${_bld}...${_rst}"
    # - for more, see the csi_strvars function:
    # [[ -n ${_cbo-} ]] || csi_strvars -pd
    _bld=$'\e[1m'
    _dim=$'\e[2m'
    _rst=$'\e[0m'

    # main command should be first non-option arg
    i=1
    while [[ ${!i} == -* ]]
    do
        let "i++"
    done
    cmd=${!i}
    set -- "${@:1:$i-1}" "${@:$i+1}"

    # NB, apt vs apt-get, apt-cache, etc:
    # - apt prints an annoying message about having an unstable API for scripts,
    #   therefore using apt subcommands is probably better & safer where possible.
    # - however, the message can also be filtered, e.g.:
    #   ... 2> >(sed '1,3 d' >&2)

    _acsearch() (
        # Search for packages and display them with metadata

        # get list of packages using search
        pkgs=( $(apt-cache search "$@" | sed -E 's/([^ ]+) - .+/\1/') )

        # call other tools to get more info
        typeset -i n_pkgs=${#pkgs[@]}

        if [[ $n_pkgs -gt 0 ]]
        then
            out_txt=$(
            for pkg in "${pkgs[@]}"
            do
                # progress indicator
                printf >&2 'Getting info for %d packages...        \r' $n_pkgs

                # installation status
                # - format in square brackets, boldify "installed"
                inst_str=$(_pinstd "$pkg" | \
                    sed -E "2 d; /not-installed/ d
                            s/^(installed)(.*)\$/[${_bld}\1${_rst}\2]/")

                # get relevant info, hold description for last for easier reading.

                # TODO: if package is installed, get the descrip from dpkg (-l)

                apt-cache show "$pkg" | \
                    sed -nE "/^Package: / {
                                 s/^(.*): (.*)\$/${_bld}\2${_rst}/ ; h; d; }
                                 # next should be version or source, not status
                                 #n; /^Status:/ { s/.*//; x
                                 #               :a; s/.*//; n; /^./ b a; /^\$/ d; }
                             # add version string to pkg name on the same line
                             /^Version: / { s/^Version:// ; H
                                            g; s/\n//; h; d; }
                             # stash short description at the start of the hold space
                             /^Description-en: / { s/^Description-en: (.*)/  \1/
                                                   x; H; d; }
                             # append these to hold text, with installation status
                             /^Section: / { s/^Section: (.*)/ ${_dim}(\1, / ; H; d; }
                             /^Priority: / { s/^Priority: (.*)/\1)${_rst} $inst_str/ ; H
                                           # print info line + short desc, quit
                                             g; s/[^\n]+\n(.+)/\1/; s/\n//g ; p
                                             g; s/([^\n]+\n).+/\1/; p; q; }
                            "
                n_pkgs=n_pkgs-1
            done
            )
            # erase progress line
            printf >&2 '                                       \r'

            # display search result with info
            less -F < <(printf '\n%s\n\n' "$out_txt")
        else
            printf >&2 "Nothing found.\n"
        fi
    )

    _pinstd() {
        # Print installation status of package
        # - uses dpkg-query; a "no packages found" message indicates a package
        #   is not installed, and maybe never has been (no config, etc)
        if stt=$(dpkg-query --show -f '${Status}\n' "$@" 2>&1)
        then
            if [[ $stt == *installed && -n $(apt-mark showmanual "$@") ]]
            then
                inst_str="installed, manual"$'\n'"$stt"

            elif [[ $stt == *installed && -n $(apt-mark showauto "$@") ]]
            then
                inst_str="installed, automatic"$'\n'"$stt"
            else
                inst_str=$stt
            fi

        elif grep -q 'no packages found matching' <<<"$stt"
        then
            inst_str="not-installed"
        else
            inst_str=$stt  # can be "not-installed" for a previously removed pkg
        fi

        printf '%s\n' "$inst_str"
    }

    _lsupgr() {
        # Show a list of packages with pending upgrades

        # options: """short" output, or major-versions only
        local shrt_op major
        local OPT OPTARG OPTIND=1
        while getopts ':sm' OPT
        do
            case $OPT in
                ( s ) shrt_op=True ;;
                ( m ) major=True ;;
                ( '?' ) echo >&2 "Unrecognized: '$OPTARG'"; return 2 ;;
            esac
        done
        shift $(( OPTIND - 1 ))

        # NB one official tool, 'apt-check -p' from update-notifier, uses the
        # python API to do this. Its functionality could be replicated by
        # getting a list of installed packages (e.g. dpkg --get-selections),
        # and then checking each one, e.g. by running 'apt cache policy $pkg'
        # and comparing the versions for 'Installed:' vs 'Candidate:'.
        #
        # From the CLI, it seems easier to parse the output of a dry-run upgrade,
        # using -V (versions) to get 1 package per line:
        ug_lns=$( apt-get upgrade --dry-run --with-new-pkgs -V --show-upgraded "$@" )

        # Check for held back packages
        grep -q 'The following packages have been kept back:' <<< "$ug_lns" \
            && {
            printf '%s\n' \
                "Some packages have upgrades but are held back." \
                "Run e.g. 'aptx snug' to see the list."
        }

        # Grab the lines detailing the upgraded packages
        ug_pkgs=$( sed -nE '/The following packages will be upgraded:/,/^[^ ]/ p' <<< "$ug_lns" )

        # - pull no. of upgrades from the last line
        # ug_n=$( tail -n 1 <<< "$ug_pkgs" \
                    # | sed -E 's/^([0-9]+) upgraded,.+$/\1/' )
        ug_n=$( sed -nE '$ { s/^([0-9]+) upgraded,.+$/\1/; p; }' <<< "$ug_pkgs" )

        # - generate ug_n string
        local ug_n_str pword=package
        [[ $ug_n -gt 1 ]] && pword=${pword}s
        ug_n_str="$ug_n $pword can be upgraded"

        if [[ -n ${shrt_op-}  &&  $ug_n -gt 24 ]]
        then
            # "short" output requested, just print n for large n
            printf '\n%s\n' "${ug_n_str}. Run 'aptx lsu' or 'lsum' to see a list."

        elif [[ $ug_n -gt 0 ]]
        then
            # - strip first and last lines
            ug_pkgs=$( sed '1 d; $ d' <<< "$ug_pkgs" )

            # if only major updates requested, filter the list
            [[ -z ${major-} ]] || {
                local awk_src=$( dirname "$( physpath "${BASH_SOURCE[0]}" )" )/apt_filt_ud.awk
                ug_pkgs=$( awk -f "$awk_src" - <<< "$ug_pkgs" )

                # count major upgrades
                local ug_n_mjr
                ug_n_mjr=$( wc -l <<< "$ug_pkgs" )
                ug_n_str+=" ($ug_n_mjr non-trivial)"
            }

            # check if any (major) upgrades remaining in list
            if [[ -n ${major-}  &&  ug_n_mjr -eq 0 ]]
            then
                printf '%s\n' "No major upgrades."

            else
                # print the upgrades list
                printf '\n%s\n' "${ug_n_str}:"

                # - emphasize package names
                sed -E "s/([ ]+)([^ ]+) /\1${_bld}\2${_rst} /" <<< "$ug_pkgs"
                printf '\n'
            fi
        else
            printf '%s\n' "All packages are up to date."
        fi
    }

    _agug() (
        # run apt-get upgrade in various flavours
        ugcmd=upgrade
        [[ $1 == --full ]] && {

            ugcmd=full-upgrade
            shift
        }

        # check for --skb = suppress kept back
        skb=False
        if ln=$(printf '%s\n' "$@" | grep -n -- '^--skb')
        then
            skb=True
            ln=$(sed -E 's/([0-9]+):.*/\1/' <<< "$ln")
            set -- "${@:1:$ln-1}" "${@:$ln+1}"
        fi

        if [[ $skb == True ]]
        then
            # TODO: run and filter apt, rather than apt-get
            run_priv apt-get $ugcmd "$@" | \
                sed -E '/^The following packages have been kept back:/,/^[^ ]/ {
                            /^The following.+kept back:/ { p; s/.*/  .../; p; d; }
                            /^[^ ]/ { p; d; }
                            /^ / d; }'
        else
            run_priv apt-get $ugcmd "$@"
        fi
    )

    _acrdepi() {
        # reverse dependencies
        apt-cache rdepends --installed "$@"
    }

    _dpq() {
        # use dpkg query to get package(s) status (brief preferred)
        # - provide grep pattern as arg:
        #   ' rc ' for deinstalled, configured
        #   ' ..R ' for broken, reinstall required
        local gpat=$1
        shift

        # two options for getting package status (can provide package glob pattern):
        # - -s (status) : dpkg -s | grep -B1 'deinstall ok config-files'
        # - -l (list)   : dpkg -l | grep '^rc'
        # with dpkg-query --show, can set format, unlike -l:
        # - use -f '...' to set format
        # - default is '${binary:Package}\t${Version}\n'
        # - possibly useful fields:
        #   Package Conffiles Status db:Status-Abbrev binary:Summary binary:Package

        # get formatted list of packages
        local dpq_out=$(dpkg-query --show \
                        -f '${Package;36} ${db:Status-Abbrev;4} ${Version;-20} ${binary:Summary;-64}\n' \
                        "$@")

        # filter for pattern matches
        local dpq_flt=$(fgrep --color=never "$gpat" <<<"$dpq_out")

        # print list
        if [[ -n $dpq_flt ]]
        then
            # headers
            printf '%36s %4s %-20s %-64s\n' "Package" "Stat" "Version" "Description" \
                "----------------------------------" "----" "--------------------" \
                "--------------------------------------------------------------"

            printf '%s\n' "$dpq_flt"
        else
            echo "Nothing found."
        fi
    }

    case $cmd in
        ( ud | update )
            #run_priv apt update "$@" 2> >(sed '1,3 d' >&2) | \
            #    sed -E "s/('apt list --upgradable')/\1 or '$FUNCNAME lsu'/"

            # de-emphasize useless parts of the URL to convey information
            run_priv apt-get update "$@" | \
                sed -E "# dim Get, Hit, Ign
                        s/^(Get:|Hit:|Ign:)/${_dim}\1${_rst}/
                        # dim http(s):// and other URL parts
                        s/^([^ ]+) ([^ ]+:\/\/[^.]+.)([^/ ]+)(\/[^ ]* | )/\1 ${_dim}\2${_rst}\3${_dim}\4${_rst}/
                        # dim everything after the 3rd field
                        s/^([^ ]+) ([^ ]+) ([^ ]+) (.*)\$/\1 \2 \3 ${_dim}\4${_rst}/
                    "

            # show a list of packages with pending upgrades, similar to apt
            # - use sed to boldify the package name
            _lsupgr -s
        ;;
        ( ug | upgrade )
            _agug "$@"
        ;;
        ( nug )
            # safe option, between ug and fug
            _agug --with-new-pkgs "$@"
        ;;
        ( fug | full-upgrade | dist-upgrade )
            # per the source code, these are synonyms
            _agug --full "$@"
        ;;
        ( snug )
            # simulate upgrade using trivial-only
            _agug --with-new-pkgs --trivial-only "$@"  \
                2> >( sed 's/E: Trivial Only specified but this is not a trivial operation.//' >&2 )
        ;;
        ( in | install )
            run_priv apt install "$@"
        ;;
        ( inma )
            run_priv apt install --mark-auto "$@"
        ;;
        ( inis )
            run_priv apt install --install-suggests "$@"
        ;;
        ( innr )
            run_priv apt install --no-install-recommends "$@"
        ;;
        ( arm )
            run_priv apt autoremove "$@"
        ;;
        ( ap )
            run_priv apt autopurge "$@"
        ;;
        ( cc )
            run_priv apt clean "$@"
            run_priv apt autoclean "$@"
        ;;
        ( prc )
            # purge residual-config
            # - get list of rc packages
            rc_list=( $( dpkg -l | grep '^rc' | sed -E 's/^rc  ([^ ]+) .*/\1/' | tr '\n' ' ' ) )

            # - purge
            run_priv apt purge "${rc_list[@]}"
            unset rc_list
        ;;
        ( lsi | listi )
            apt list --installed "$@"
        ;;
        ( lsu | listu )
            #apt list --upgradable "$@"
            _lsupgr "$@"
        ;;
        ( lsum )
            #apt list --upgradable "$@"
            _lsupgr -m "$@"
        ;;
        ( lsm | listm )
            # apt shows a fair bit of info, and quickly
            apt list --manual-installed "$@"
        ;;
        ( lsm2 | listm2 )
            # apt-mark shows a plain list, but really quickly
            apt-mark showmanual "$@"
        ;;
        ( lsh | listh | showhold )
            apt-mark showhold "$@"
        ;;
        ( lsrc )
            _dpq ' rc ' "$@"
        ;;
        ( lsb )
            _dpq ' ..R ' "$@"
        ;;
        ( s | search)
            _acsearch "$@"
        ;;
        ( sn | sno )
            _acsearch -n "$@"
        ;;
        ( show | info | sh | i | status )
            # parse the output to emphasize description and labels
            # - for installed packages, a-c-show prints dpkg -p <pkg> as well
            apt-cache show "$@" | \
                sed -E "1 { s/^(Package: )(.+)/${_bld}\1\2${_rst}/; p; d; }
                        /^Description-[[:alpha:]]+:/,/^Description-md5:/ {H; d; }
                        # on empty line, print Desc preceded by md5
                        /^$/ { g; s/^\n(.+\n)(Description-md5: .+)/\2\n\1/; }
                        # if you hit 'Package:' again (from 'dpkg -p' call),  quit
                        /^Package: / { s/.*//; q; }
                        # otherwise, boldify the key string
                        s/(^|\n)([[:alnum:]-]+: )/${_bld}\1\2${_rst}/g"

            inst_str=$(_pinstd "$@" | \
                        sed -E '2 s/^/        /')
            printf '%s %s\n\n' "${_bld}Status:${_rst}" "$inst_str"

            # if installed, show conf-files
            grep -q '^installed' <<< "$inst_str" && {

                cf_str=$(dpkg -s "$@" | \
                            sed -nE "/^Conffiles:/,/^[^ ]/ {
                                        /^(Conf| )/! d
                                        s/^([[:alnum:]-]+:)/${_bld}\1${_rst}/
                                        p; }")
                [[ -n $cf_str ]] && {

                    printf '%s\n\n' "$cf_str"
                }
            }

            apt-cache policy "$@" | \
                sed -E "1 s/^(.+):$/${_bld}Policy for \1:${_rst}/"
        ;;
        ( rdepi )
            # reverse dependencies
            _acrdepi "$@"
        ;;
        ( rdepir | why )
            # recursive rdeps
            _acrdepi --recurse --no-{conflicts,breaks,replaces,enhances} "$@"
        ;;
        ( rdepirns | iwhy )
            # reverse dependencies
            _acrdepi --recurse --no-{conflicts,breaks,replaces,enhances} \
                --no-suggests "$@"
        ;;
        ( hist | history )
            less "$@" /var/log/apt/history.log
        ;;
        ( hold )
            run_priv apt-mark hold "$@"
        ;;
        ( unhold )
            run_priv apt-mark unhold "$@"
        ;;
        ( markauto )
            run_priv apt-mark auto "$@"
        ;;
        ( markman )
            run_priv apt-mark manual "$@"
        ;;
        ( r )
            run_priv apt "$@"
        ;;
        ( * )
            err_msg 2 "Unknown command: '$cmd'" \
                    "Run '$FUNCNAME -h' for cmd help, or rerun using" \
                    "'$FUNCNAME r $cmd ...' to run 'apt $cmd ...'."
            return 2
        ;;
    esac
)
