#!/usr/bin/env bash
LOCAL_PATH=$(cd $(dirname ${0}) && pwd && cd - &> /dev/null)
BASE_PATH=${LOCAL_PATH}

function get_param() {
    value=$(grep ${1} ${BASE_PATH}/conf/param.conf |grep -v '^ *#' |awk -F '"' '{print $2}')
    echo ${value}
}

function get_avg_lst() {
    lst=($@)
    sum=0
    for i in "${lst[@]}"
    do
        ((sum=sum+i))
    done
    ((avg=sum/${#lst[@]}))
    echo ${avg}
}

function convert_time_to_second() {
    real_time=$1
    convert_time=0
    echo ${real_time} |grep 'm' &> /dev/null
    if [ $? -ne 0 ]; then
        convert_time=$(echo ${real_time} |cut -d'.' -f1)
    else
        echo ${real_time} |grep 'ms' &> /dev/null
        if [ $? -ne 0 ]; then
            echo ${real_time} |grep 'h' &> /dev/null
            if [ $? -ne 0 ]; then
                m=$(echo ${real_time} |awk -F '[m.]' '{print $1}')
                s=$(echo ${real_time} |awk -F '[m.]' '{print $2}')
                ((convert_time=m*60+s))
            else
                h=$(echo ${real_time} |awk -F '[hm.]' '{print $1}')
                m=$(echo ${real_time} |awk -F '[hm.]' '{print $2}')
                s=$(echo ${real_time} |awk -F '[hm.]' '{print $3}')
                ((convert_time=h*3600+m*60+s))
            fi
        fi
    fi
    echo ${convert_time}
}


