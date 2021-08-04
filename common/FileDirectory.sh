#!/usr/bin/env bash

LOCALDIR=$(cd $(dirname $0) && pwd && cd - &> /dev/null)
BASEDIR=$(cd ${LOCALDIR}/.. && pwd && cd - &> /dev/null)
source ${BASEDIR}/Common/Log.sh

function remove_file(){
  file=$1
  if [ -n "${file}" ]; then
    rm -rf ${file}
    if [ ! -f "${file}" ]; then
      log_info "removing file ${file} success!"
      return_value=0
    else
      log_info "removing file ${file} failed!"
      return_value=1
    fi
  else
    log_info "file: ${file} not exist! pass!"
    return_value=0
  fi
  return ${return_value}
}

function remove_directory(){
  directory=$1
  if [ -n "${directory}" ]; then
    rm -rf ${directory}
    if [ ! -d "${directory}" ]; then
      log_info "removing directory ${directory} success!"
      return_value=0
    else
      log_info "removing directory ${directory} failed!"
      return_value=1
    fi
  else
    log_info "directory: ${directory} not exist! pass!"
    return_value=0
  fi
  return ${return_value}
}

function is_directory_exist() {
    dir=$1
    if [ -d "${dir}" ]; then
      log_info "found directory: ${dir}"
      return_value=0
    else
      log_err "directory: ${dir} not exist"
      return_value=1
    fi
    return ${return_value}
}

function is_file_exist() {
    file=$1
    if [ -f "${file}" ]; then
      log_info "found file: ${file}"
      return_value=0
    else
      log_err "file: ${file} not exist"
      return_value=1
    fi
    return ${return_value}
}

function check_str_timeout() {
    # TO DO ...
    file=$1
    str="$2"
    grep "${str}" ${file}
}