#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

URL_TEMPLATE="https://aws.amazon.com/api/dirs/items/search?item.directoryId=deepracer-leaderboard&sort_by=item.additionalFields.position&sort_order=asc&size=100&item.locale=en_US&tags.id=deepracer-leaderboard%23recordtype%23individual&tags.id=deepracer-leaderboard%23eventtype%23virtual&tags.id=deepracer-leaderboard%23eventid%23virtual-season-"

SEASONS="2019-05 2019-06 2019-07"

USERNAME=${CIRCLE_PROJECT_USERNAME:-nalbam}
REPONAME=${CIRCLE_PROJECT_REPONAME:-deepracer}

GIT_USERNAME="bot"
GIT_USEREMAIL="bot@nalbam.com"

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

    mkdir -p ${SHELL_DIR}/build
    mkdir -p ${SHELL_DIR}/leaderboard

    if [ -f ${SHELL_DIR}/build/points.log ]; then
        rm -rf ${SHELL_DIR}/build/points.log
    fi
}

_build() {
    for SEASON in ${SEASONS}; do
        _command "_build ${SEASON}"

        URL="${URL_TEMPLATE}${SEASON}"

        curl -sL ${URL} \
            | jq -r '.items[].item | "\"\(.additionalFields.racerName)\" \(.additionalFields.lapTime) \(.additionalFields.points)"' \
            > ${SHELL_DIR}/build/leaderboard_${SEASON}.log
    done

    for SEASON in ${SEASONS}; do
        _command "_build ${SEASON} additional"

        LOG_FILE=${SHELL_DIR}/build/leaderboard_${SEASON}.log

        JDX=1
        while read LINE; do
            ARR=(${LINE})

            NAME="$(echo ${ARR[0]} | cut -d'"' -f2)"

            for SVAL in ${SEASONS}; do
                LOG_TEMP=${SHELL_DIR}/build/leaderboard_${SVAL}.log

                COUNT=$(cat ${LOG_TEMP} | grep "\"${NAME}\"" | wc -l | xargs)

                if [ "x${COUNT}" != "x0" ]; then
                    continue
                fi

                URL="${URL_TEMPLATE}${SVAL}&item.additionalFields.racerName=${NAME}"

                curl -sL ${URL} \
                    | jq -r '.items[].item | "\"\(.additionalFields.racerName)\" \(.additionalFields.lapTime) \(.additionalFields.points)"' \
                    >> ${LOG_TEMP}

                # _result "${SVAL} ${NAME}"
            done

            if [ "${JDX}" == "30" ]; then
                break
            fi

            JDX=$(( ${JDX} + 1 ))
        done < ${LOG_FILE}
    done

    _command "_build summary"

    FIRST_SEASON="$(echo $SEASONS | cut -d' ' -f1)"

    while read LINE; do
        ARR=(${LINE})

        NAME="$(echo ${ARR[0]} | cut -d'"' -f2)"
        TIME="${ARR[1]}"
        POINTS="${ARR[2]}"

        for SEASON in ${SEASONS}; do
            if [ "${SEASON}" == "${FIRST_SEASON}" ]; then
                continue
            fi

            LOG_FILE=${SHELL_DIR}/build/leaderboard_${SEASON}.log

            ARR=($(cat ${LOG_FILE} | grep "\"${NAME}\"" | head -1))

            SUB_TIME="${ARR[1]}"
            SUB_POINTS="${ARR[2]}"

            if [ "${SUB_TIME}" != "" ]; then
                if [ "${SUB_POINTS}" == "null" ]; then
                    # SUB_POINTS=$(perl -e "print 1000-${ARR[1]:3}")
                    SUB_POINTS=$(echo "1000-${ARR[1]:3}" | bc)
                fi

                # POINTS=$(perl -e "print ${POINTS}+${SUB_POINTS}")
                POINTS=$(echo "${POINTS}+${SUB_POINTS}" | bc)
            fi
        done

        echo "${POINTS} ${NAME}" >> ${SHELL_DIR}/build/points.log
    done < ${SHELL_DIR}/build/leaderboard_${FIRST_SEASON}.log

    # backup
    if [ -f ${SHELL_DIR}/leaderboard/points.log ]; then
        cp ${SHELL_DIR}/leaderboard/points.log ${SHELL_DIR}/build/backup.log
    fi

    # print
    cat ${SHELL_DIR}/build/points.log | sort -r -g | head -25 > ${SHELL_DIR}/leaderboard/points.log
}

_message() {
    _command "_message"

    MESSAGE=${SHELL_DIR}/build/message.tmp
    README=${SHELL_DIR}/build/readme.tmp

    echo "| # | Score | RacerName |   |" > ${README}
    echo "| - | ----- | --------- | - |" >> ${README}

    IDX=1
    while read LINE; do
        COUNT=$(cat ${SHELL_DIR}/build/backup.log | grep "${LINE}" | wc -l | xargs)

        ARR=(${LINE})

        if [ "x${COUNT}" != "x0" ]; then
            echo "${IDX}\t${ARR[0]}\t${ARR[1]}" >> ${MESSAGE}
            echo "| ${IDX} | ${ARR[0]} | ${ARR[1]} | |" >> ${README}
        else
            CHANGED=true

            _result "changed ${ARR[0]} ${ARR[1]}"

            echo "${IDX}\t${ARR[0]}\t${ARR[1]}\t<<<<<<<" >> ${MESSAGE}
            echo "| ${IDX} | ${ARR[0]} | ${ARR[1]} | * |" >> ${README}
        fi

        IDX=$(( ${IDX} + 1 ))
    done < ${SHELL_DIR}/leaderboard/points.log

    # message
    echo "*DeepRacer Virtual Circuit Scoreboard*" > ${SHELL_DIR}/build/message.log
    cat ${MESSAGE} >> ${SHELL_DIR}/build/message.log

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

_git_push() {
    _command "_git_push"

    if [ -z ${GITHUB_TOKEN} ]; then
        return
    fi

    DATE=$(date +%Y%m%d-%H%M)

    git config --global user.name "${GIT_USERNAME}"
    git config --global user.email "${GIT_USEREMAIL}"

    git add --all
    git commit -m "${DATE}"

    git push -q https://${GITHUB_TOKEN}@github.com/${USERNAME}/${REPONAME}.git master
}

_slack() {
    _command "_slack"

    if [ -z ${SLACK_TOKEN} ]; then
        return
    fi

    json="{\"text\":\"$(cat ${SHELL_DIR}/build/message.log)\"}"

    webhook_url="https://hooks.slack.com/services/${SLACK_TOKEN}"
    curl -s -d "payload=${json}" "${webhook_url}"
}

__main__() {
    _prepare

    _build
    _message

    if [ ! -z ${CHANGED} ]; then
        _git_push
        _slack
    fi

    _success
}

__main__
