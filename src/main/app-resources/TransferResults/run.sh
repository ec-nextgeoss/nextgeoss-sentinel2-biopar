#!/bin/bash

# source the ciop functions (e.g. ciop-log, ciop-getparam)
source ${ciop_job_include}
source ${_CIOP_APPLICATION_PATH}/TransferResults/lib/functions.sh

trap cleanExit EXIT

# Input references come from STDIN (standard input) and they are retrieved
# line-by-line.
nbInputs=0

while read input
do
  let nbInputs=nbInputs+1
  main ${input} || exit $?
done

if [ $nbInputs -eq 0 ]; then
    exit $ERR_NOINPUT
fi
