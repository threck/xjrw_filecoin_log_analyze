#!/usr/bin/env bash
LOCAL_PATH=$(cd $(dirname ${0}) && pwd && cd - &> /dev/null)
BASE_PATH=${LOCAL_PATH}

sector_nu=$1
if [ -z "${sector_nu}" ]; then
    echo "please run as: [ $0 <sector_nu> <run_type> ]. "
    echo "sector_nu : sector number per turn"
    echo "run_type : analyzation type: a new or a old analyzation? default: new"
    exit 1
fi
run_type=$2
if [ -z "${run_type}" ]; then
    run_type="new"
elif [[ "$run_type" != "new" ]] || [[ "$run_type" != "old" ]]; then
    echo "please run as: [ $0 <sector_nu> <run_type> ]. run_type default: new"
    exit 1
elif [ ! -f "${BASE_PATH}/log/miner.log" ]; then
    echo "first time please run as: [ $0 <sector_nu> <run_type> ]. run_type default: new"
fi

# shellcheck source=/dev/null
source "${BASE_PATH}"/common/Log.sh
# shellcheck source=/dev/null
source "${BASE_PATH}"/common/NetWork.sh
# shellcheck source=/dev/null
source "${BASE_PATH}"/common/Common.sh

function print_warning() {
    cat << EOF
#######################################
warning!!!
before continue
you must make sure you've write all workers' ip-nodename info into file:/etc/hosts!!
#######################################
EOF
}

user=$(get_param "user")
pwd=$(get_param "pwd")
lotus_miner=$(get_param "lotus_miner")
miner_source_log=$(get_param "miner_log")
miner_target_log="${BASE_PATH}/log/miner.log"
worker_source_log=$(get_param "worker_log")
nodenames=$(${lotus_miner} sealing workers |grep Worker |awk '{print $4}')
filecoin_cluster_info="${BASE_PATH}/tmp/filecoin_cluster_info.tmp"

# gen filecoin_cluster_info file
mkdir -p "${BASE_PATH}"/tmp
rm -rf "${BASE_PATH}"/tmp/filecoin_cluster_info.tmp
for nodename in ${nodenames}
do
    tmp_ip=$(grep ${nodename} /etc/hosts |awk '{print $1}')
    tmp_worker_type=$(${lotus_miner} sealing workers |grep Worker |grep ${nodename} |awk '{print $6}')
    if [[ ${tmp_worker_type} == "tasks" ]]; then
        tmp_worker_state="disable"
        tmp_worker_type=$(${lotus_miner} sealing workers |grep Worker |grep ${nodename} |awk '{print $7}')
    else
        tmp_worker_state="online"
    fi
    echo "${tmp_ip} ${nodename} ${tmp_worker_type} ${tmp_worker_state}" >> ${filecoin_cluster_info}
done

################
# prepare some logs
################
if [[ "${run_type}" == "new" ]]; then
    # 1. miner.log
    cp ${miner_source_log} ${miner_target_log}
    # 2. worker.log
    for ip in $(cat ${filecoin_cluster_info} |awk '{print $1}')
    do
        nodename_tmp=$(grep ${ip} ${filecoin_cluster_info} |awk '{print $2}')
        sync_from_remote ${ip} ${user} ${pwd} ${worker_source_log} ${BASE_PATH}/log/worker_${nodename_tmp}.log
    done
fi

################
# gen some logs
################
# 1. sealing_sector.log
rm -rf ${BASE_PATH}/log/sealing_sector.log
sector_ids=$(grep assign ${miner_target_log} |awk '{print $9}' |cut -d'}' -f1 |sort |uniq)
for sector_id in ${sector_ids}
do
    ${lotus_miner} sectors status --log ${sector_id} >> ${BASE_PATH}/log/sealing_sector.log 2>1&
done

# 2. sealing_time.log
for nodename in $(cat ${filecoin_cluster_info} |awk '{print $2}')
do
    {
    echo "AP:"
    grep cast ${miner_target_log} |grep AddPiece  # of ap
    echo "P1:"
    grep cast ${miner_target_log} |grep SealPreCommit1  # of p1
    echo "P2:"
    grep cast ${miner_target_log} |grep SealPreCommit2  # of p2
    echo "C1:"
    grep cast ${miner_target_log} |grep SealCommit1  # of c1
    echo "C2:"
    grep cast ${miner_target_log} |grep SealCommit2  # of c2
    } >  "${BASE_PATH}/log/sealing_time.log"
done

##################
# gen summary_<NODENAME>.txt
##################
# function define
function get_sector_id_of_phase() {
    nodename=$1
    phase=$2
    # assign sectors
    assign_sectors=$(grep assign ${miner_target_log} |grep ${nodename} |grep /${phase} |awk '{print $9}' |cut -d'}' -f1 |sort |uniq)
    normal_seal_sectors=()
    abnormal_seal_sectors=()
    sealing_sectors=()
    for sector in ${assign_sectors}
    do
        grep " ${sector}\}" "${BASE_PATH}/log/sealing_time.log" &> /dev/null
        if [ $? -eq 0 ];then
            line=$(grep " ${sector}\}" "${BASE_PATH}/log/sealing_time.log" |wc -l)
            if [ "${line}" -ne 1 ]; then
                # abnormal seal sectors
                abnormal_seal_sectors[${#abnormal_seal_sectors[@]}]=${sector}
            else
                # normal seal sectors
                normal_seal_sectors[${#normal_seal_sectors[@]}]=${sector}
            fi
        else
            # sealing sectors
            sealing_sectors[${#sealing_sectors[@]}]=${sector}
        fi
    done
    echo "${phase}:"
    echo "assign_sectors:" "${assign_sectors}"
    echo "normal_seal_sectors:" "${normal_seal_sectors[@]}"
    echo "abnormal_seal_sectors:" "${abnormal_seal_sectors[@]}"
    echo "sealing_sectors:" "${sealing_sectors[@]}"
    echo "normal_seal_sectors:${phase}:" "${normal_seal_sectors[@]}" > ${BASE_PATH}/log/normal_sealed_${nodename}.log
}

function get_average_time() {
    nodename=$1
    phase=$2
    sectors=$(grep "normal_seal_sectors:${phase}" ${BASE_PATH}/log/normal_sealed_${nodename}.log |awk -F':' '{print $3}')
    lst_time=()
    for i in ${sectors}
    do
        real_time=$(grep " ${i}\} " "${BASE_PATH}/log/sealing_time.log" |awk '{print $12}')
        echo ${real_time} |grep "ms" &> /dev/null
        if [ $? -ne 0 ]; then
            real_time=$(convert_time_to_second ${real_time})
            lst_time[${#lst_time[@]}]=${real_time}
        fi
    done
    echo $(get_avg_lst "${lst_time}")
}

# kinds of sectors list
for nodename in $(cat ${filecoin_cluster_info} |awk '{print $2}')
do
    {
    # gen sectors info for each stage
    get_sector_id_of_phase "${nodename}" 'addpiece'
    get_sector_id_of_phase "${nodename}" 'precommit/1'
    get_sector_id_of_phase "${nodename}" 'precommit/2'
    get_sector_id_of_phase "${nodename}" 'commit/1'
    get_sector_id_of_phase "${nodename}" 'commit/2'

    # sector is sealing on ssd or mem
    woker_target_log="${BASE_PATH}/log/worker_${nodename_tmp}.log"
    sector_on_ssd=$(grep 'is ssd:true' ${woker_target_log} |awk '{print $6}' |awk -F"[-\\\]]" '{print $3}' |sort |uniq)
    sector_on_mem=$(grep 'is ssd:false' ${woker_target_log} |awk '{print $6}' |awk -F"[-\\\]]" '{print $3}' |sort |uniq)
    echo "sector_on_ssd: ${sector_on_ssd}"
    echo "sector_on_mem: ${sector_on_mem}"

    # summary
    ip=$(grep ${nodename} /etc/hosts |awk '{print $1}')
    sector_size=$(${lotus_miner} info |grep Miner: |awk '{print $3" "$4}' |cut -d'(' -f2)

    average_ap=$(get_average_time ${nodename} "addpiece")
    average_p1=$(get_average_time ${nodename} "precommit/1")
    average_p2=$(get_average_time ${nodename} "precommit/2")
    average_c1=$(get_average_time ${nodename} "commit/1")
    average_c2=$(get_average_time ${nodename} "commit/2")


    # p2_eat_p1_nu_theory
    p2_eat_p1_nu_theory=$(echo "scale=2;${average_p1}/${average_p2}" |bc)
    # p2_eat_p1_nu_actual
    if [ ${p2_eat_p1_nu_theory} -le ${sector_nu} ]; then
        p2_eat_p1_nu_actual=${p2_eat_p1_nu_theory}
    else
        p2_eat_p1_nu_actual=${sector_nu}
    fi

    harvest_theory=$(echo "scale=2;24*3600/${average_p1}*${p2_eat_p1_nu_actual}*${sector_size}/1024" |bc)

    # round_per_day_theory=$()
    # round_per_day_actual=$()
    # harvest_actual=$()
    cat << EOF
    nodename:${nodename}, ip:${ip}, sector_size:${sector_size}, task_nu:${sector_nu}
    average_ap:${average_ap}
    average_p1:${average_p1}
    average_p2:${average_p2}
    average_c1:${average_c1}
    average_c2:${average_c2}
    p2_eat_p1_nu_theory:${p2_eat_p1_nu_theory}
    p2_eat_p1_nu_actual:${p2_eat_p1_nu_actual}
    harvest_theory:${harvest_theory}
EOF
    } > "${BASE_PATH}/log/summary_${nodename}.txt"
done


