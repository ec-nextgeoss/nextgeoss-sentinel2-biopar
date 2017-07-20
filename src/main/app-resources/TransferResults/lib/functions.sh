#!/bin/bash

# define the exit codes
SUCCESS=0
ERR_TRANSFER=60
ERR_INPUT_COPY=61

###############################################################################
# Trap function to exit gracefully
###############################################################################
function cleanExit ()
{
  local retval=$?
  local msg=""
  case "${retval}" in
    ${SUCCESS})         msg="Transferring Sentinel2 Biopar products successfully concluded";;
    ${ERR_TRANSFER})    msg="Failed to transfer the Sentinel2 Biopar products";;
    ${ERR_INPUT_COPY})  msg="Failed to copy input Sentinel2 Biopar products";;
    *) msg="Unknown error";;
  esac

  [ "${retval}" != "0" ] && ciop-log "ERROR" "Error ${retval} - ${msg}, transferring aborted" || ciop-log "INFO" "${msg}"
  exit ${retval}
}

###############################################################################
# Main function to transfer the results published by the previous node.
###############################################################################
function main() {
  
  local input=$1
  local outputDir=${TMPDIR}/s2-biopar-output

  mkdir -p ${outputDir}

  s2BioparProduct=$(echo $input | ciop-copy -U -o ${outputDir} -)
  s2BioparProductBasename=$(basename ${s2BioparProduct})

  # Check if the copy was successfull
  [ $? -eq 0 ] && [ -n "${s2BioparProduct}" ] || return ${ERR_INPUT_COPY}
  
  # Transfer Sentinel2 Biopar product
  docker run \
       -v ${outputDir}:/home/worker/workDir/outDir                                    \
       vito-docker-private.artifactory.vgt.vito.be/nextgeoss-sentinel2-biopar:latest  \
       /home/worker/s2-biopar/transferProduct.sh /home/worker/workDir/outDir/${s2BioparProductBasename}

  [ $? -eq 0 ] || return $ERR_TRANSFER

  # Cleanup temporary results
  rm -rf ${s2BioparProduct}

  return ${SUCCESS}
}
