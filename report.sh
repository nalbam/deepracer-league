#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

URLS=${SHELL_DIR}/urls.txt
COUNT=$(cat ${URLS} | wc -l | xargs)

SEASONS=("2019-05 2019-06 2019-07")

_prepare() {
    mkdir -p ${SHELL_DIR}/build
    mkdir -p ${SHELL_DIR}/target

    if [ -f ${SHELL_DIR}/build/points.log ]; then
        rm -rf ${SHELL_DIR}/build/points.log
    fi
}

_build() {
    IDX=1
    while read URL; do
        LOG_FILE=${SHELL_DIR}/build/leaderboard_100_${IDX}.log

        curl -sL ${URL} \
            | jq -r '.items[].item | "\"\(.additionalFields.racerName)\" \(.additionalFields.lapTime) \(.additionalFields.points)"' \
            > ${SHELL_DIR}/build/leaderboard_100_${IDX}.log

        curl -sL ${URL} \
            | jq -r '.items[].item | "\"\(.additionalFields.racerName)\" \(.additionalFields.lapTime) \(.additionalFields.points)"' \
            | head -20 \
            > ${SHELL_DIR}/leaderboard/${IDX}.log

        IDX=$(( ${IDX} + 1 ))
    done < ${URLS}

    for IDX in {1..3}; do
        LOG_FILE=${SHELL_DIR}/build/leaderboard_100_${IDX}.log

        JDX=1
        while read LINE; do
            ARR=(${LINE})

            NAME="$(echo ${ARR[0]} | cut -d'"' -f2)"

            for KDX in {1..3}; do
                LOG_TEMP=${SHELL_DIR}/build/leaderboard_100_${KDX}.log

                COUNT=$(cat ${LOG_TEMP} | grep "\"${NAME}\"" | wc -l | xargs)

                if [ "x${COUNT}" != "x0" ]; then
                    continue
                fi

                URL="$(cat ${URLS} | head -${KDX} | tail -1 | xargs)"

                # echo "${KDX} ${NAME} ${COUNT}    "${URL}"&item.additionalFields.racerName=${NAME}"

                # curl -sL ${URL}"&item.additionalFields.racerName=${NAME}" | jq .

                curl -sL ${URL}"&item.additionalFields.racerName=${NAME}" \
                    | jq -r '.items[].item | "\"\(.additionalFields.racerName)\" \(.additionalFields.lapTime) \(.additionalFields.points)"' \
                    >> ${LOG_TEMP}
            done

            if [ "${JDX}" == "30" ]; then
                break
            fi

            JDX=$(( ${JDX} + 1 ))
        done < ${LOG_FILE}
    done

    while read LINE; do
        ARR=(${LINE})

        NAME="$(echo ${ARR[0]} | cut -d'"' -f2)"
        TIME="${ARR[1]}"
        POINTS="${ARR[2]}"

        for IDX in {2..3}; do
            LOG_FILE=${SHELL_DIR}/build/leaderboard_100_${IDX}.log

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
    done < ${SHELL_DIR}/build/leaderboard_100_1.log


    echo "*DeepRacer Virtual Circuit*" > ${SHELL_DIR}/target/message.log
    cat ${SHELL_DIR}/build/points.log | sort -r -g | head -20 | nl >> ${SHELL_DIR}/target/message.log

    cat ${SHELL_DIR}/target/message.log
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

_slack
