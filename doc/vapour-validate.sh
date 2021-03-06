#!/bin/sh -eux

# This is an example warden validation job for a fake customer.

CUSTOMER_NAME=vapour

: ${RELIC_STORE:="s3://ambiata-prod-live-state/${CUSTOMER_NAME}/relic/view"}
: ${WARDEN_STORE:="s3://ambiata-prod-live-state/${CUSTOMER_NAME}/warden"}
: ${INPUT:="s3://ambiata-prod-view/${CUSTOMER_NAME}"}
: ${OUTPUT:="s3://ambiata-prod-view/${CUSTOMER_NAME}"}
: ${FEEDS:="foo_feed bar_feed"}
: ${DATE:=$(TZ="Australia/Sydney" date +"%Y-%m-%d")}
: ${DAYS:=15}

export TMPDIR=${O2_WORK_DIR}/tmp
mkdir -p ${TMPDIR}

cd ${TMPDIR}

usage () {
    cat <<EOF
usage: o2 dist \$(vee vapour-validate latest)
EOF
    exit 1
}

[ "$#" == 0 ] ||  usage

FAILURE_MARKER=$(pwd)/warden-has-failures

for FEED_NAME in ${FEEDS}; do
(
    set -eux

    WORKDIR=$(mktemp -d -p ${TMPDIR} wardenXXXXXX)
    FEEDDIR=${WORKDIR}/${FEED_NAME}
    mkdir -p ${FEEDDIR}
    cd ${WORKDIR}

    HAVE_FILES=0

    relic list \
          --ignore-meta \
          --store-root ${RELIC_STORE} \
          --name ${FEED_NAME} \
          --view-root ${INPUT} \
          --tag-category "validate=unprocessed" \
          --date ${DATE} \
          --last-n-days ${DAYS} | tee ${WORKDIR}/warden-files | {\
    while read F; do
        HAVE_FILES=1
        s3 download ${INPUT}/${FEED_NAME}/${F} ${FEEDDIR}/${F}
    done

    # Don't fail if there's nothing for us to validate.
    if [ $HAVE_FILES -eq 1 ]; then
        set +e
        warden check -v -r 10000 -d -s \| ${FEED_NAME}
        warden_exit=$?
        set -e

        if [ ! $warden_exit -eq 0 ]; then
            touch $FAILURE_MARKER
        fi

        aws s3 cp --recursive _warden ${WARDEN_STORE} --sse

        cat ${WORKDIR}/warden-files | \
            while read F; do
                FN=$(basename ${F})
                DN=$(dirname ${F})
                MARKER="${DN}/_${FN}.warden"
                s3 upload ${FEED_NAME}/${MARKER} \
                   ${OUTPUT}/${FEED_NAME}/${MARKER}
                relic mark \
                      --store-root ${RELIC_STORE} \
                      --name ${FEED_NAME} \
                      --tag validate \
                      --done \
                      -d ${F}
            done
    fi
    }
)
done

if [ -f $FAILURE_MARKER ]; then
    exit 1
fi

