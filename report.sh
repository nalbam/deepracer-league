#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

MODE=$1

URL_TEMPLATE="https://aws.amazon.com/api/dirs/items/search?item.directoryId=deepracer-leaderboard&sort_by=item.additionalFields.position&sort_order=asc&size=100&item.locale=en_US&tags.id=deepracer-leaderboard%23recordtype%23individual&tags.id=deepracer-leaderboard%23eventtype%23virtual&tags.id=deepracer-leaderboard%23eventid%23virtual-season-"

SEASONS="2019-05 2019-06 2019-07 2019-08 2019-09 2019-10"

FIRST="2019-05"
LATEST="2019-10"

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
    exit 1
}

_prepare() {
    _command "_prepare"

    rm -rf ${SHELL_DIR}/build

    if [ "${MODE}" == "clear" ]; then
        rm -rf ${SHELL_DIR}/cache
    fi

    mkdir -p ${SHELL_DIR}/build
    mkdir -p ${SHELL_DIR}/cache

    if [ -f ${SHELL_DIR}/build/points.log ]; then
        rm -rf ${SHELL_DIR}/build/points.log
    fi

    echo
}

_load_leaderboard() {
    # leaderboard
    for SEASON in ${SEASONS}; do
        _command "_build ${SEASON}"

        CACHE_FILE=${SHELL_DIR}/cache/${SEASON}.log

        if [ -f ${CACHE_FILE} ] && [ "${SEASON}" != "${LATEST}" ]; then
            _result "_build ${SEASON} cached"
            continue
        fi

        URL="${URL_TEMPLATE}${SEASON}"

        curl -sL ${URL} \
            | jq -r '.items[].item | "\(.additionalFields.lapTime) \"\(.additionalFields.racerName)\" \(.additionalFields.points)"' \
            > ${CACHE_FILE}

        _result "_build ${SEASON} loaded"
    done

    echo
}

_load_extra() {
    SEASON=$1

    _command "_build ${SEASON} extra"

    CACHE_FILE=${SHELL_DIR}/cache/${SEASON}.log

    if [ ! -f ${CACHE_FILE} ]; then
        _result "_build ${SEASON} not found"
        continue
    fi

    JDX=1
    while read LINE; do
        NAME="$(echo ${LINE} | cut -d'"' -f2)"

        for SVAL in ${SEASONS}; do
            if [ "${SVAL}" == "${SEASON}" ]; then
                continue
            fi

            LOG_TEMP=${SHELL_DIR}/cache/${SVAL}.log

            COUNT=$(cat ${LOG_TEMP} | grep "\"${NAME}\"" | wc -l | xargs)

            if [ "x${COUNT}" != "x0" ]; then
                continue
            fi

            URL="${URL_TEMPLATE}${SVAL}&item.additionalFields.racerName=${NAME}"

            curl -sL ${URL} \
                | jq -r '.items[].item | "\(.additionalFields.lapTime) \"\(.additionalFields.racerName)\" \(.additionalFields.points)"' \
                >> ${LOG_TEMP}

            _result "_build ${SVAL} ${NAME}"
        done

        # if [ "${JDX}" == "50" ]; then
        #     break
        # fi

        JDX=$(( ${JDX} + 1 ))
    done < ${CACHE_FILE}
}

_load_extras() {
    # extra
    for SEASON in ${SEASONS}; do
        _load_extra ${SEASON}
    done

    echo
}

_build_summary() {
    # summary
    _command "_build summary"

    while read LINE; do
        ARR=(${LINE})

        NAME="$(echo ${LINE} | cut -d'"' -f2)"

        TIME="${ARR[0]}"
        POINTS="${ARR[2]}"

        for SEASON in ${SEASONS}; do
            if [ "${SEASON}" == "${FIRST}" ]; then
                continue
            fi

            CACHE_FILE=${SHELL_DIR}/cache/${SEASON}.log

            if [ ! -f ${CACHE_FILE} ]; then
                _result "_build ${SEASON} not found"
                continue
            fi

            ARR=($(cat ${CACHE_FILE} | grep "\"${NAME}\"" | head -1))

            SUB_TIME="${ARR[0]}"
            SUB_POINTS="${ARR[2]}"

            if [ "${SUB_TIME}" != "" ]; then
                if [ "${SUB_POINTS}" == "null" ]; then
                    SUB_POINTS=$(echo "1000-60*${ARR[0]:0:2}-${ARR[0]:3}" | bc)
                fi

                POINTS=$(echo "${POINTS}+${SUB_POINTS}" | bc)
            fi
        done

        echo "${POINTS} ${NAME}" >> ${SHELL_DIR}/build/points.log
    done < ${SHELL_DIR}/cache/${FIRST}.log

    # backup
    if [ -f ${SHELL_DIR}/cache/points.log ]; then
        cp ${SHELL_DIR}/cache/points.log ${SHELL_DIR}/build/backup.log
    fi

    # print
    cat ${SHELL_DIR}/build/points.log | sort -r -g | head -35 > ${SHELL_DIR}/cache/points.log

    echo
}

_build() {
    _load_leaderboard

    if [ "${MODE}" == "clear" ]; then
        _load_extras
    fi

    _build_summary
}

_message() {
    _command "_message"

    MESSAGE=${SHELL_DIR}/build/message.tmp
    README=${SHELL_DIR}/build/readme.tmp

    echo "| # | Score | RacerName |   |" > ${README}
    echo "| - | ----- | --------- | - |" >> ${README}

    IDX=1
    while read LINE; do
        if [ -f ${SHELL_DIR}/build/backup.log ]; then
            COUNT=$(cat ${SHELL_DIR}/build/backup.log | grep "${LINE}" | wc -l | xargs)
        else
            COUNT="0"
        fi

        ARR=(${LINE})

        if [ "x${COUNT}" != "x0" ]; then
            echo "${IDX}\t${ARR[0]}\t${ARR[1]}\n" >> ${MESSAGE}
            echo "| ${IDX} | ${ARR[0]} | ${ARR[1]} | |" >> ${README}
        else
            CHANGED=true

            _result "changed ${ARR[0]} ${ARR[1]}"

            echo "${IDX}\t${ARR[0]}\t${ARR[1]}\t<<<\n" >> ${MESSAGE}
            echo "| ${IDX} | ${ARR[0]} | ${ARR[1]} | <<< |" >> ${README}
        fi

        IDX=$(( ${IDX} + 1 ))
    done < ${SHELL_DIR}/cache/points.log

    echo

    # message
    echo "*DeepRacer Virtual Circuit Scoreboard*\n" > ${SHELL_DIR}/build/message.log
    cat ${MESSAGE} >> ${SHELL_DIR}/build/message.log

    # slack message
    json="{\"text\":\"$(cat ${SHELL_DIR}/build/message.log)\"}"
    echo $json > ${SHELL_DIR}/build/slack_message.json

    # commit message
    printf "$(date +%Y%m%d-%H%M)" > ${SHELL_DIR}/build/commit_message.txt

    # readme
    IDX=1
    while read LINE; do
        COUNT="$(echo ${LINE} | grep "\-\- leaderboard \-\-" | wc -l | xargs)"

        if [ "x${COUNT}" != "x0" ]; then
            break
        fi

        IDX=$(( ${IDX} + 1 ))
    done < ${SHELL_DIR}/README.md

    sed "${IDX}q" ${SHELL_DIR}/README.md > ${SHELL_DIR}/build/readme.md
    cat ${README} >> ${SHELL_DIR}/build/readme.md

    if [ ! -z ${CHANGED} ]; then
        cp -rf ${SHELL_DIR}/build/readme.md ${SHELL_DIR}/README.md
    fi
}

_json() {
    _command "_json"

    JSON=${SHELL_DIR}/cache/points.json

    echo "{\"deepracer\":[" > ${JSON}

    IDX=1
    while read LINE; do
        ARR=(${LINE})

        if [ "${IDX}" != "1" ]; then
            echo "," >> ${JSON}
        fi

        printf "{\"no\":${IDX},\"name\":\"${ARR[1]}\",\"point\":${ARR[0]}}" >> ${JSON}

        IDX=$(( ${IDX} + 1 ))
    done < ${SHELL_DIR}/build/points.log

    echo "]}" >> ${JSON}
}

__main__() {
    _prepare

    _build
    _message

    # _json

    if [ -z ${CHANGED} ]; then
        _error "not changed."
    fi

    _success
}

__main__
