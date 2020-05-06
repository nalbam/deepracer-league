#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

URL_TEMPLATE="https://aws.amazon.com/api/dirs/items/search?item.directoryId=deepracer-leaderboard&sort_by=item.additionalFields.position&sort_order=asc&size=100&item.locale=en_US&tags.id=deepracer-leaderboard%23recordtype%23individual&tags.id=deepracer-leaderboard%23eventtype%23virtual&tags.id=deepracer-leaderboard%23eventid%23"

# SEASONS="2020-03-tt 2020-03-oa 2020-03-h2h"

# SEASON=$1

CHANGED=

# command -v tput > /dev/null && TPUT=true
TPUT=

_echo() {
    if [ "${TPUT}" != "" ] && [ "$2" != "" ]; then
        echo -e "$(tput setaf $2)$1$(tput sgr0)"
    else
        echo -e "$1"
    fi
}

_result() {
    _echo "# $@" 4
}

_command() {
    _echo "$ $@" 3
}

_success() {
    _echo "+ $@" 2
    exit 0
}

_error() {
    _echo "- $@" 1
    # exit 1
}

_prepare() {
    _command "_prepare"

    # rm -rf ${SHELL_DIR}/build

    mkdir -p ${SHELL_DIR}/build
    mkdir -p ${SHELL_DIR}/cache

    echo
}

_load() {
    LEAGUE=$1
    SEASON=$2
    FILENAME=$3

    _command "_load ${SEASON} ..."

    if [ -f ${SHELL_DIR}/cache/${FILENAME}.log ]; then
        cat ${SHELL_DIR}/cache/${FILENAME}.log > ${SHELL_DIR}/build/${FILENAME}.log
    fi

    URL="${URL_TEMPLATE}${SEASON}"

    curl -sL ${URL} \
        | jq -r '.items[].item | "\(.additionalFields.lapTime) \"\(.additionalFields.racerName)\" \(.additionalFields.points)"' \
        > ${SHELL_DIR}/cache/${FILENAME}.log

    _result "_load ${SEASON} done"

    echo
}

_build() {
    LEAGUE=$1
    SEASON=$2
    FILENAME=$3

    CHANGED=

    _command "_build ${SEASON} ..."

    MESSAGE=${SHELL_DIR}/build/slack_message-${LEAGUE}.json

    echo "{\"blocks\":[" > ${MESSAGE}
    echo "{\"type\":\"section\",\"text\":{\"type\":\"mrkdwn\",\"text\":\"*AWS Virtual Circuit - ${SEASON}*\"}}," >> ${MESSAGE}

    RACERS=${SHELL_DIR}/build/racers.txt

    cat ${SHELL_DIR}/racers.json \
        | jq -r '.[] | "\(.racername) \(.username)"' \
        > ${RACERS}

    while read LINE; do
        ARR=(${LINE})

        if [ -f ${SHELL_DIR}/cache/${FILENAME}.log ]; then
            RECORD="$(cat ${SHELL_DIR}/cache/${FILENAME}.log | grep "${ARR[0]}")"

            ARR2=(${RECORD})

            RACER=$(echo "${ARR2[1]}" | sed -e 's/^"//' -e 's/"$//')

            if [ -f ${SHELL_DIR}/cache/${FILENAME}-racers.log ]; then
                ARR3=($(cat ${SHELL_DIR}/cache/${FILENAME}-racers.log | grep "${ARR[0]}" | tail -1))

                if [ "${ARR2[0]}" != "${ARR3[0]}" ]; then
                    echo "${RECORD}" >> ${SHELL_DIR}/cache/${FILENAME}-racers.log

                    CHANGED=true

                    TEXT="${ARR2[0]}    ~${ARR3[0]}~    ${RACER}"
                    echo "{\"type\":\"context\",\"elements\":[{\"type\":\"mrkdwn\",\"text\":\"${TEXT}\"}]}," >> ${MESSAGE}
                fi
            else
                echo "${RECORD}" >> ${SHELL_DIR}/cache/${FILENAME}-racers.log

                CHANGED=true

                echo "{\"type\":\"context\",\"elements\":[{\"type\":\"mrkdwn\",\"text\":\"${RECORD}\"}]}," >> ${MESSAGE}
            fi
        fi
    done < ${RACERS}

    echo "{\"type\":\"divider\"}" >> ${MESSAGE}
    echo "]}" >> ${MESSAGE}

    if [ "${CHANGED}" == "" ]; then
        rm -rf ${MESSAGE}
        _error "Not changed"
    fi

    # commit message
    printf "$(date +%Y%m%d-%H%M)" > ${SHELL_DIR}/build/commit_message.txt

    _result "_build ${SEASON} done"

    echo
}

_run() {
    _prepare

    LIST=${SHELL_DIR}/build/league.txt

    cat ${SHELL_DIR}/league.json \
        | jq -r '.[] | "\(.league) \(.season) \(.filename)"' \
        > ${LIST}

    while read LINE; do
        ARR=(${LINE})

        _load ${ARR[0]} ${ARR[1]} ${ARR[2]}
        _build ${ARR[0]} ${ARR[1]} ${ARR[2]}
    done < ${LIST}

    _success
}

_run
