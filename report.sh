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

_prepare() {
    mkdir -p ${SHELL_DIR}/build
    mkdir -p ${SHELL_DIR}/leaderboard

    if [ -f ${SHELL_DIR}/build/points.log ]; then
        rm -rf ${SHELL_DIR}/build/points.log
    fi
}

_build() {
    for SEASON in ${SEASONS}; do
        # echo ${SEASON}

        URL="${URL_TEMPLATE}${SEASON}"

        curl -sL ${URL} \
            | jq -r '.items[].item | "\"\(.additionalFields.racerName)\" \(.additionalFields.lapTime) \(.additionalFields.points)"' \
            > ${SHELL_DIR}/build/leaderboard_${SEASON}.log
    done

    for SEASON in ${SEASONS}; do
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
            done

            if [ "${JDX}" == "30" ]; then
                break
            fi

            JDX=$(( ${JDX} + 1 ))
        done < ${LOG_FILE}
    done

    FIRST_SEASON="$(echo $SEASONS | cut -d' ' -f1)"

    # collect
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
                    SUB_POINTS=$(perl -e "print 1000-${ARR[1]:3}")
                fi

                POINTS=$(perl -e "print ${POINTS}+${SUB_POINTS}")
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
            echo "${IDX}\t${ARR[0]}\t${ARR[1]}\t<<<<<<<" >> ${MESSAGE}
            echo "| ${IDX} | ${ARR[0]} | ${ARR[1]} | * |" >> ${README}
        fi

        IDX=$(( ${IDX} + 1 ))
    done < ${SHELL_DIR}/leaderboard/points.log

    # message
    echo "*DeepRacer Virtual Circuit*" > ${SHELL_DIR}/build/message.log
    cat ${MESSAGE} >> ${SHELL_DIR}/build/message.log

    cat ${SHELL_DIR}/build/message.log

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

    cp -rf ${SHELL_DIR}/build/readme.md ${SHELL_DIR}/README.md
}

_git_push() {
    if [ -z ${GITHUB_TOKEN} ]; then
        return
    fi

    DATE=$(date +%Y%m%d-%H%M)

    git config --global user.name "${GIT_USERNAME}"
    git config --global user.email "${GIT_USEREMAIL}"

    git add --all
    git commit -m "${DATE}" > /dev/null 2>&1 || export CHANGED=true

    if [ -z ${CHANGED} ]; then
        git push -q https://${GITHUB_TOKEN}@github.com/${USERNAME}/${REPONAME}.git master

        _slack
    fi
}

_slack() {
    if [ -z ${SLACK_TOKEN} ]; then
        return
    fi

    json="{\"text\":\"$(cat ${SHELL_DIR}/target/message.log)\"}"

    webhook_url="https://hooks.slack.com/services/${SLACK_TOKEN}"
    curl -s -d "payload=${json}" "${webhook_url}"
}

_prepare

_build

_message

_git_push
