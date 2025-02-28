#!/usr/bin/env bash

MOTUS2_VERSION="2.1.1"
MOTUS2_DOWNLOAD="https://github.com/motu-tool/mOTUs_v2/archive/${MOTUS2_VERSION}.tar.gz"

if ! which python >/dev/null ; then
    echo "python command not found"
    exit 1
fi

if ! which mktemp >/dev/null ; then
    echo "mktemp command not found"
    exit 1
fi

if ! which getopt >/dev/null ; then
    echo "getopt command not found"
    exit 1
fi

if ! which sed >/dev/null ; then
    echo "sed command not found"
    exit 1
fi

if ! which cut >/dev/null ; then
    echo "cut command not found"
    exit 1
fi

if ! python -c 'import sys; not (sys.version_info.major == 3) and sys.exit(1)' >/dev/null ; then
    echo "Incompatible python version: need 3.x"
    exit 1
fi

if [[ -z "$1" ]] ; then
    if [ ! -d "$NGLESS_MODULE_DIR/mOTUs_v2" ]; then
        echo "mOTUs_v2 profiler not found. Please run the following command to install:"
        echo "cd $NGLESS_MODULE_DIR && wget $MOTUS2_DOWNLOAD && tar xf ${MOTUS2_VERSION}.tar.gz && rm -f ${MOTUS2_VERSION}.tar.gz && mv mOTUs_v2-${MOTUS2_VERSION} mOTUs_v2 && cd mOTUs_v2 && python setup.py"
        exit 1
    fi
else
    # Parsing arguments passed
    ARG_PARSE="getopt -o s:Io:t:a -l sample:,speci_only,ofile:,taxonomic_level:,rel_abund -n $0 --"

    # We process arguments twice to handle any argument parsing error:
    ARG_ERROR=$($ARG_PARSE "$@" 2>&1 1>/dev/null)

    if [ $? -ne 0 ]; then
        echo >&2 "${ERROR} $ARG_ERROR"
        echo >&2 ""
        exit 1
    fi

    # Abort on any errors from this point onwards
    set -e

    # Parse args using getopt (instead of getopts) to allow arguments before options
    ARGS=$($ARG_PARSE "$@")

    # reorganize arguments as returned by getopt
    eval set -- "$ARGS"

    # Initialize default values
    SAMPLE=""
    SPECI=""
    OUTPUT=""
    # motus 2.0.0 changed the default to relative abundance. It was counts before.
    # With this change and in order to not break API from our side, we default
    # to -c (counts) and unset RELABUND if user asked for --rel_abund
    RELABUND="-c"
    TAXLEVEL=""

    while true; do
        case "$1" in
            # Shift before to throw away option
            # Shift after if option has a required positional argument
            -s|--sample)
                shift
                SAMPLE="$1"
                shift
                ;;
            -I|--speci_only)
                shift
                SPECI="-e"
                ;;
            -a|--rel_abund)
                shift
                RELABUND=""
                ;;
            -o|--ofile)
                shift
                OUTPUT="$1"
                shift
                ;;
            -t|--taxonomic_level)
                shift
                TAXLEVEL="$1"
                shift
                ;;
            --)
                shift
                break
                ;;
        esac
    done

    # forward, reverse and single reads
    if [[ ! -z "$1" ]] ; then
        READS="-s $1"
        if [[ ! -z "$2" ]] ; then
            READS="-f $1 -r $2"
            if [[ ! -z "$3" ]] ; then
                READS="$READS -s $3"
            fi
        fi
    fi

    BWA="$($NGLESS_NGLESS_BIN --print-path bwa)"
    SAMTOOLS="$($NGLESS_NGLESS_BIN --print-path samtools)"

    # link binaries into PATH to force motus profiler to use them
    TMPDIR="$(mktemp -d)"
    if [ "${TMPDIR}x" = "x" ]; then
        echo "Failed to create temporary directory"
        exit 1
    fi

    TMPBINDIR="${TMPDIR}/bin"
    mkdir -p "${TMPBINDIR}"
    ln -s "$BWA"      "${TMPBINDIR}/bwa"
    ln -s "$SAMTOOLS" "${TMPBINDIR}/samtools"

    export PATH=$TMPBINDIR:$PATH

    "$NGLESS_MODULE_DIR/mOTUs_v2/motus" profile \
        ${SPECI} \
        $RELABUND \
        -t "$NGLESS_NR_CORES" \
        -k "${TAXLEVEL}" \
        -n "${SAMPLE}" \
        -o "${TMPBINDIR}/output.txt" \
        ${READS}

    # Convert to conform to NGLess' expectations:
    #  1. Add header
    #  2. Remove comments
    #  3. sort (must be done in C locale!)
    (printf "\t${SAMPLE}\n" ;  sed '/^\#/d'  < "${TMPBINDIR}/output.txt" | LC_ALL=C sort)> "${OUTPUT}"

    rm -rf "${TMPDIR}"
fi
