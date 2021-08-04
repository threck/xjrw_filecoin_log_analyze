#!/usr/bin/env bash

function log_info() {
  echo $(date '+%Y-%m-%d %H:%M:%S')" [INFO] - $1"
}

function log_err() {
  echo $(date '+%Y-%m-%d %H:%M:%S')" [ERROR] - $1"
}

function log_warn() {
  echo $(date '+%Y-%m-%d %H:%M:%S')" [WARN] - $1"
}