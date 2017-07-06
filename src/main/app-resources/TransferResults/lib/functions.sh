#!/bin/bash

# FTP server settings
FTP_TRANSFER_MODE=1             # transfer mode (0|1 = sftp|ftp)
FTP_USER='s2-biopar'
FTP_PASSWORD='Bio_20s!'
FTP_HOST='cvbftp.vgt.vito.be'
FTP_DIR='s2-biopar-nextgeoss'

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
  local inputDir=${TMPDIR}/s2-biopar-input

  mkdir -p ${inputDir}

  s2BioparProduct=$( echo $input | ciop-copy -U -o ${inputDir} - )

  # Check if the copy was successfull
  [ $? -eq 0 ] && [ -n "${s2BioparProduct}" ] || return ${ERR_INPUT_COPY}
  
  ciop-log "INFO" "Transferring Sentinel2 Biopar products: ${s2BioparProduct}"

  s2BioparLocalDir=`dirname ${s2BioparProduct}`
  s2BioparBaseName=`basename ${s2BioparProduct}`

  if [ $FTP_TRANSFER_MODE -eq 0 ]; then

      # Use SFTP as transfer protocol
      
      sftp ${FTP_USER}@${FTP_HOST} -b << EOT

          cd ${FTP_DIR}
          lcd ${s2BioparLocalDir}
          put ${s2BioparBaseName}

          bye
          
EOT

  elif [ $FTP_TRANSFER_MODE -eq 1 ]; then

      # Use FTP as transfer protocol

      ftp -n -v $FTP_HOST << EOT

        user ${FTP_USER} ${FTP_PASSWORD}
        binary
        cd ${FTP_DIR}
        lcd ${s2BioparLocalDir}
        put ${s2BioparBaseName}
        
        bye

EOT

  fi

  [ $? -eq 0 ] || return $ERR_TRANSFER

  # Cleanup temporary results
  rm -rf ${s2BioparProduct}

  return ${SUCCESS}
}
