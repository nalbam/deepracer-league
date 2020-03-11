#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

URL_TEMPLATE="https://aws.amazon.com/api/dirs/items/search?item.directoryId=deepracer-leaderboard&sort_by=item.additionalFields.position&sort_order=asc&size=100&item.locale=en_US&tags.id=deepracer-leaderboard%23recordtype%23individual&tags.id=deepracer-leaderboard%23eventtype%23virtual&tags.id=deepracer-leaderboard%23eventid%23virtual-season-"

SEASONS="2020-03-tt 2020-03-oa 2020-03-h2h"

# SEASON=$1

G_CHANGED=

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
    exit 1
}

_prepare() {
    _command "_prepare"

    rm -rf ${SHELL_DIR}/build

    mkdir -p ${SHELL_DIR}/build
    mkdir -p ${SHELL_DIR}/cache

    echo
}

_build() {
    for SEASON in ${SEASONS}; do
        _load ${SEASON}
        _message ${SEASON}
    done
}

_load() {
    SEASON=$1

    _command "_load ${SEASON} ..."

    if [ -f ${SHELL_DIR}/cache/${SEASON}.log ]; then
        cp -rf ${SHELL_DIR}/cache/${SEASON}.log ${SHELL_DIR}/build/${SEASON}.log
    fi

    URL="${URL_TEMPLATE}${SEASON}"

    curl -sL ${URL} \
        | jq -r '.items[].item | "\(.additionalFields.lapTime) \"\(.additionalFields.racerName)\" \(.additionalFields.points)"' \
        > ${SHELL_DIR}/cache/${SEASON}.log

    _result "_load ${SEASON} done"

    echo
}

_message() {
    SEASON=$1

    _command "_message ${SEASON} ..."

    MESSAGE=${SHELL_DIR}/build/message-${SEASON}.tmp

    CHANGED=

    IDX=1
    while read LINE; do
        if [ -f ${SHELL_DIR}/build/${SEASON}.log ]; then
            COUNT=$(cat ${SHELL_DIR}/build/${SEASON}.log | grep "${LINE}" | wc -l | xargs)
        else
            COUNT="0"
        fi

        ARR=(${LINE})

        NO=$(printf %02d $IDX)
        RACER=$(echo "${ARR[1]}" | sed -e 's/^"//' -e 's/"$//')

        if [ "x${COUNT}" != "x0" ]; then
            echo "${NO}\t${ARR[0]}\t${RACER}\n" >> ${MESSAGE}
        else
            CHANGED=true

            _result "changed ${ARR[0]} ${RACER}"

            echo "${NO}\t${ARR[0]}\t${RACER}\t<<<\n" >> ${MESSAGE}
        fi

        if [ "${IDX}" == "20" ]; then
            break
        fi

        IDX=$(( ${IDX} + 1 ))
    done < ${SHELL_DIR}/cache/${SEASON}.log

    echo

    if [ "${CHANGED}" == "" ]; then
        return
    fi

    G_CHANGED=true

    # message
    echo "*AWS Virtual Circuit - ${SEASON}*\n" >> ${SHELL_DIR}/build/message.log
    cat ${MESSAGE} >> ${SHELL_DIR}/build/message.log
    echo "\n" >> ${SHELL_DIR}/build/message.log
}

_slack() {
    if [ "${G_CHANGED}" == "" ]; then
        _error "Not changed"
    fi

    # slack message
    json="{\"text\":\"$(cat ${SHELL_DIR}/build/message.log)\"}"
    echo $json > ${SHELL_DIR}/build/slack_message.json

    # commit message
    printf "$(date +%Y%m%d-%H%M)" > ${SHELL_DIR}/build/commit_message.txt
}

_run() {
    _prepare

    _build

    _slack

    _success
}

_run
