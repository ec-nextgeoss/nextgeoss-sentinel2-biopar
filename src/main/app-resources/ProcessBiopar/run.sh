#!/bin/bash

source ${_CIOP_APPLICATION_PATH}/ProcessBiopar/lib/functions.sh

trap cleanExit EXIT

# Input references come from STDIN (standard input) and they are retrieved
# line-by-line.
while read input
do
  ciop-log "INFO" "The input is: ${input}"
  main ${input} || exit $?
done
