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
elif [[ "$run_type" != "new" ]] && [[ "$run_type" != "old" ]]; then
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
print_warning
user=$(get_param "user")
pwd=$(get_param "pwd")
lotus_miner=$(get_param "lotus_miner")
miner_source_log=$(get_param "miner_log")
miner_target_log="${BASE_PATH}/log/miner.log"
worker_source_log=$(get_param "worker_log")
filecoin_cluster_info="${BASE_PATH}/tmp/filecoin_cluster_info.tmp"
sealing_jobs_log="${BASE_PATH}/log/sealing_jobs.log"

mkdir -p "${BASE_PATH}"/tmp
mkdir -p "${BASE_PATH}"/summary
mkdir -p "${BASE_PATH}"/log

if [[ "${run_type}" == "new" ]]; then
    # gen filecoin_cluster_info file if run_type is new
    log_info "create filecoin_cluster_info: ${filecoin_cluster_info}"
    nodenames=$(${lotus_miner} sealing workers |grep Worker |grep -v RD |awk '{print $4}')
    sector_size=$(${lotus_miner} info |grep Miner: |awk '{print $3" "$4}' |cut -d'(' -f2)

    rm -rf ${filecoin_cluster_info}
    echo "${sector_size}" >> ${filecoin_cluster_info}
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
else
    # get filecoin_cluster_info file if run_type is old
    nodenames=$(grep -v 'GiB' ${filecoin_cluster_info} |awk '{print $2}')
    sector_size=$(grep 'GiB' ${filecoin_cluster_info} |awk '{print $1}')
fi

################
# prepare some logs
################
if [[ "${run_type}" == "new" ]]; then
    # 1. miner.log
    log_info "backup miner.log ..."
    cp ${miner_source_log} ${miner_target_log}
    # 2. worker.log
    for ip in $(cat ${filecoin_cluster_info} |grep -v GiB |awk '{print $1}')
    do
        nodename_tmp=$(grep ${ip} ${filecoin_cluster_info} |awk '{print $2}')
        sync_from_remote ${ip} ${user} ${pwd} ${worker_source_log} ${BASE_PATH}/log/worker_${nodename_tmp}.log
    done
    # 3. sealing jobs log
    log_info "create ${sealing_jobs_log} ..."
    ${lotus_miner} sealing jobs &> ${sealing_jobs_log}
fi

################
# gen some logs
################
# 1. sealing_sector.tmp
rm -rf ${BASE_PATH}/tmp/sealing_sector.tmp
sector_ids=$(grep assign ${miner_target_log} |awk '{print $9}' |cut -d'}' -f1 |sort |uniq)
mkdir -p ${BASE_PATH}/tmp/sealing_sectors
for sector_id in ${sector_ids}
do
    ${lotus_miner} sectors status --log ${sector_id} &> ${BASE_PATH}/tmp/sealing_sectors/${sector_id}.tmp &
done

# 2. sealing_time.tmp
for nodename in $(cat ${filecoin_cluster_info} |grep -v GiB |awk '{print $2}')
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
    } >  "${BASE_PATH}/tmp/sealing_time.tmp"
done

##################
# gen summary_<NODENAME>.txt
##################
# function define
function get_sector_id_of_phase() {
    nodename=$1
    phase=$2
    [[ "${phase}" == "AddPiece" ]] && phase_low="addpiece" && phase_simple="AP"
    [[ "${phase}" == "SealPreCommit1" ]] && phase_low="precommit/1" && phase_simple="PC1"
    [[ "${phase}" == "SealPreCommit2" ]] && phase_low="precommit/2" && phase_simple="PC2"
    [[ "${phase}" == "SealCommit1" ]] && phase_low="commit/1" && phase_simple="C1"
    [[ "${phase}" == "SealCommit2" ]] && phase_low="commit/2" && phase_simple="C2"
    # assign sectors
    assign_sectors=$(grep assign ${miner_target_log} |grep ${nodename} |grep /${phase_low} |awk '{print $9}' |cut -d'}' -f1 |sort |uniq)
    assign_sectors_nu=()
    normal_seal_sectors=()
    abnormal_seal_sectors=()
    sealing_sectors=()
    waiting_sectors=()
    for sector in ${assign_sectors}
    do
        assign_sectors_nu[${#assign_sectors_nu[@]}]=${sector}
        line=$(grep " ${sector}\} " "${BASE_PATH}/tmp/sealing_time.tmp" |grep ${phase} |wc -l)
        grep " ${sector} " ${sealing_jobs_log} |grep running |grep " ${phase_simple} " &> /dev/null
        is_running=$?
        if [ "${line}" -eq 1 ] && [ "${is_running}" -ne 0 ]; then
            # normal seal sectors
            normal_seal_sectors[${#normal_seal_sectors[@]}]=${sector}
        elif [ "${line}" -gt 1 ] && [ "${is_running}" -ne 0  ]; then
            # abnormal seal sectors
            abnormal_seal_sectors[${#abnormal_seal_sectors[@]}]=${sector}
        elif [ "${is_running}" -eq 0 ]; then
            # sealing sectors
            sealing_time_tmp=$(grep " ${sector} " ${sealing_jobs_log} |grep running |grep " ${phase_simple} " |awk '{print $7}')
            sealing_sectors[${#sealing_sectors[@]}]="${sector}(${sealing_time_tmp})"
        else
            # waiting sectors
            waiting_sectors[${#waiting_sectors[@]}]=${sector}
        fi
    done

    echo "--------------"
    echo "${phase}:"
    echo "--------------"
    echo "assign_sectors(${#assign_sectors_nu[@]}):" "${assign_sectors_nu[@]}"
    echo "normal_seal_sectors(${#normal_seal_sectors[@]}):" "${normal_seal_sectors[@]}"
    echo "abnormal_seal_sectors(${#abnormal_seal_sectors[@]}):" "${abnormal_seal_sectors[@]}"
    echo "sealing_sectors(${#sealing_sectors[@]}):" "${sealing_sectors[@]}"
    echo "waiting_sectors(${#waiting_sectors[@]}):" "${waiting_sectors[@]}"
    echo "normal_seal_sectors(${#normal_seal_sectors[@]}):${phase}:" "${normal_seal_sectors[@]}" >> ${BASE_PATH}/tmp/normal_sealed_${nodename}.tmp
    echo ""
}

function get_average_time() {
    nodename=$1
    phase=$2
    sectors=$(grep "${phase}" ${BASE_PATH}/tmp/normal_sealed_${nodename}.tmp |awk -F':' '{print $3}')
    lst_time=()
    for i in ${sectors}
    do
        real_time=$(grep " ${i}\} " "${BASE_PATH}/tmp/sealing_time.tmp" |grep ${phase} |awk '{print $12}')
        echo ${real_time} |grep "ms" &> /dev/null
        if [ $? -ne 0 ]; then
            real_time=$(convert_time_to_second ${real_time})
            lst_time[${#lst_time[@]}]=${real_time}
        fi
    done
    echo $(get_avg_lst "${lst_time}")
}

# kinds of sectors list
for nodename in $(cat ${filecoin_cluster_info} |grep -v GiB |awk '{print $2}')
do
    log_info "analyze ${nodename} log ."
    {
    ip=$(grep ${nodename} /etc/hosts |awk '{print $1}')

    rm -rf ${BASE_PATH}/tmp/normal_sealed_${nodename}.tmp  # clean before create a new log
    grep "${nodename}" ${filecoin_cluster_info} |grep ' C2 '
    if [ $? -ne 0 ]; then
        # gen sectors info for each stage
        get_sector_id_of_phase "${nodename}" 'AddPiece'
        get_sector_id_of_phase "${nodename}" 'SealPreCommit1'
        get_sector_id_of_phase "${nodename}" 'SealPreCommit2'
        get_sector_id_of_phase "${nodename}" 'SealCommit1'

        # sector is sealing on ssd or mem
        woker_target_log="${BASE_PATH}/log/worker_${nodename}.log"
        sector_on_ssd=$(grep 'is ssd:true' ${woker_target_log} |awk '{print $6}' |awk -F"[-\\\]]" '{print $3}' |sort |uniq)
        sector_on_ssd_nu=$(grep 'is ssd:true' ${woker_target_log} |awk '{print $6}' |awk -F"[-\\\]]" '{print $3}' |sort |uniq |wc -l)
        sector_on_mem=$(grep 'is ssd:false' ${woker_target_log} |awk '{print $6}' |awk -F"[-\\\]]" '{print $3}' |sort |uniq)
        sector_on_mem_nu=$(grep 'is ssd:false' ${woker_target_log} |awk '{print $6}' |awk -F"[-\\\]]" '{print $3}' |sort |uniq |wc -l)

        echo "###########"
        echo "# P1 TYPE #"
        echo "###########"
        echo "P1_sector_on_ssd(${sector_on_ssd_nu}):" ${sector_on_ssd}
        echo "P1_sector_on_mem(${sector_on_mem_nu}):" ${sector_on_mem}
        echo ""

        # summary
        average_ap=$(get_average_time ${nodename} "AddPiece")
        average_p1=$(get_average_time ${nodename} "SealPreCommit1")
        average_p2=$(get_average_time ${nodename} "SealPreCommit2")
        average_c1=$(get_average_time ${nodename} "SealCommit1")

        # p2_eat_p1_nu_theory
        p2_eat_p1_nu_theory=$(echo "scale=2;${average_p1}/${average_p2}" |bc)
        # p2_eat_p1_nu_actual
        if [ $(echo "${p2_eat_p1_nu_theory} <= ${sector_nu}" |bc) -eq 1 ]; then
        #if [ ${p2_eat_p1_nu_theory} -le ${sector_nu} ]; then
            p2_eat_p1_nu_actual=${p2_eat_p1_nu_theory}
        else
            p2_eat_p1_nu_actual=${sector_nu}
        fi

        harvest_theory=$(echo "scale=2;24*3600/${average_p1}*${p2_eat_p1_nu_actual}*${sector_size%% *}/1024" |bc)
        # round_per_day_theory=$()
        # round_per_day_actual=$()
        # harvest_actual=$()
        cat << EOF
###########
# SUMMARY #
###########
nodename:${nodename}, ip:${ip}, sector_size:${sector_size}, task_nu:${sector_nu}
average_ap:${average_ap}s
average_p1:$(echo "scale=2;${average_p1}/60" |bc)m
average_p2:$(echo "scale=2;${average_p2}/60" |bc)m
average_c1:${average_c1}s
p2_eat_p1_nu_theory:${p2_eat_p1_nu_theory}
p2_eat_p1_nu_actual:${p2_eat_p1_nu_actual}
harvest_theory:${harvest_theory} TiB
EOF
    else
        # gen sectors info for each stage
        get_sector_id_of_phase "${nodename}" 'SealCommit2'
        # summary
        average_c2=$(get_average_time ${nodename} "SealCommit2")
        cat << EOF
###########
# SUMMARY #
###########
nodename:${nodename}, ip:${ip}, sector_size:${sector_size}, task_nu:${sector_nu}
average_c2:$(echo "scale=2;${average_c2}/60" |bc)m

EOF
    fi
    } > "${BASE_PATH}/summary/summary_${nodename}.txt"
    log_info "analyze ${nodename} log finished."
    log_info "check summary in : [ ${BASE_PATH}/summary/summary_${nodename}.txt ]"
done

log_info "game over! bye bye"
