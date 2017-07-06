#!/bin/bash

export ciop_job_include="/usr/lib/ciop/libexec/ciop-functions.sh"
source ./test_common.sh
source ../main/app-resources/ProcessBiopar/lib/functions.sh

log_input()
{
    local input=$1
    ciop-log "INFO" "processing input: ${input}" 
}

test_log_input()
{
  local input="https://data2.terradue.com/eop/sentinel2/dataset/search?uid=S2A_OPER_PRD_MSIL1C_PDMC_20160508T221513_R008_V20160508T104027_20160508T104027"
  local log_msg=$( log_input "${input}" 2>&1 | head -n 1 )
  assertEquals "[INFO   ][user process] processing input: ${input}" "${log_msg:20}"
}

. ${SHUNIT2_HOME}/shunit2
