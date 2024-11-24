# {print}
# split(s,A,r)
# substr(s,i,n)
# match(s,r)
# gsub(r,s,t)

# main loop
{
    # process version string for lines that have it
    if ( match($0, /\([0-9].* => [0-9].*\)$/) ) {

        # capture the version string and split it on =>
        verss = substr($0, RSTART)
        if ( ! ( split(verss, versarr, / => /) == 2 ) )
            print "split failed" > "/dev/stderr"

        # remove parens
        sub(/^\(/, "", versarr[1])
        sub(/\)$/, "", versarr[2])

        # clean version no.s
        for ( i = 1; i <=2; i++ ) {
            # binary recompiles are not major
            sub(/\+b[0-9]+$/, "", versarr[i])

            # debian re-releases are not major
            sub(/-[0-9\.]+$/, "", versarr[i])
        }

        # if version scheme changed, that's major
        # - split on ':'
        nfa = split(versarr[1], verSchA, /:/)
        nfb = split(versarr[2], verSchB, /:/)

        if ( nfb > 1 ) {
            if ( ( ! nfa > 1 ) || ( verSchA[1] != verSchB[1] ) ) {
                print
                next
            }
        }

        # split each version string on .
        nfa = split(verSchA[length(verSchA)], verA, /(\.)/)
        nfb = split(verSchB[length(verSchB)], verB, /(\.)/)

        # compare first 2 fields
        if ( ( nfa < 2 ) || ( nfb < 2 ) || ( verA[1] != verB[1] ) || ( verA[2] != verB[2] ) ) {
            # # debug
            # print ""
            # print "nfa: " nfa
            # print "verA[1]: " verA[1]
            # print "verA[2]: " verA[2]

            print
            next
        }

        # # testing, debug
        # for (i in verA) {
        #     print "verA[" i "]: " verA[i]
        #     print "verB[" i "]: " verB[i]
        # }
        # print ""
    }
    else {
        # no version string found, just print line as-is
        print
    }
}
