#!/usr/bin/env bash
LOCAL_PATH=$(cd $(dirname ${0}) && pwd && cd - &> /dev/null)
BASE_PATH=${LOCAL_PATH}

sector_id=$1
if [ -z "${sector_id}" ]; then
    echo "please run as: [ $0 <sector_id> ]. "
    echo "sector_id : sector ID"
    exit 1
fi

# shellcheck source=/dev/null
source "${BASE_PATH}"/common/Log.sh
# shellcheck source=/dev/null
source "${BASE_PATH}"/common/NetWork.sh
# shellcheck source=/dev/null
source "${BASE_PATH}"/common/Common.sh

# provide info:
# sector log
sealing_time_file="${BASE_PATH}"/tmp/sealing_time.tmp
sealing_sector_dir="${BASE_PATH}"/tmp/sealing_sectors

## sector log
cat << EOF

##############
# SECTOR LOG #
##############
EOF
cat ${sealing_sector_dir}/${sector_id}.tmp

## spended time on each phase
cat << EOF

##############
# PHASE TIME #
##############
EOF
grep cast ${sealing_time_file} |grep " ${sector_id}} "

## detail log
cat << EOF

##############
# DETAIL LOG #
##############
EOF
grep "\-${sector_id}\]" "${BASE_PATH}"/log/worker_node*.log
