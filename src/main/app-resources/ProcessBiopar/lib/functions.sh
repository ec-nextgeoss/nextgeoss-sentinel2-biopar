#!/bin/bash

USE_STUB=0

# define the exit codes
SUCCESS=0
ERR_NOINPUT=50
ERR_BIOPAR=51
ERR_PUBLISH=52

# source the ciop functions (e.g. ciop-log, ciop-getparam)
source ${ciop_job_include}

###############################################################################
# Trap function to exit gracefully.
###############################################################################
function cleanExit ()
{
  local retval=$?
  local msg=""
  case "${retval}" in
    ${SUCCESS})     msg="Processing Sentinel2 Biopar products successfully concluded";;
    ${ERR_BIOPAR})  msg="Failed to generate the Sentinel2 Biopar products";;
    ${ERR_NOINPUT}) msg="Failed to download the Sentinel2 product";;
    ${ERR_PUBLISH}) msg="Failed to publish the Sentinel2 Biopar products";;
    *) msg="Unknown error";;
  esac

  [ "${retval}" != "0" ] && ciop-log "ERROR" "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  exit ${retval}
}

###############################################################################
# Main function to generate bio-physical parameters from a given Sentinel2
# product reference.
###############################################################################
function main()
{
  local input=${1}

  ciop-log "INFO" "Processing Sentinel2 Biopar products: ${input}"

  # Setup some folder to store the Sentinel2 products
  
  local inputDir=${TMPDIR}/s2-biopar-input
  local outputDir=${TMPDIR}/s2-biopar-output
  local tmpDir=${TMPDIR}/s2-biopar-tmp

  local inputDir="/home/worker/workDir/inDir" 
  local outputDir="/home/worker/workDir/outDir" 
  local tmpDir="/home/worker/workDir/tmpDir" 
 
  mkdir -p ${inputDir}
  mkdir -p ${outputDir}
  mkdir -p ${tmpDir}

  # Stage in the input file to a temporary folder that is unique for this workflow ($TMPDIR)

  if [[ ${input:0:4} == "file" ]]; then
      enclosure=${input}
  else
      enclosure="$( opensearch-client -p do=terradue ${input} enclosure )"
  fi

  rm -rf ${inputDir}/$(basename ${enclosure}) 
  s2Product=$( ciop-copy -U -o ${inputDir} "${enclosure}" )     # -U = disable automatic decompression of zip - files

  # Check if the Sentinel2 product is a symbolic link. We need to pass the input directory to the "docker run" command.
  if [ -L $s2Product ]; then
      inputDir=`dirname $(readlink $s2Product)`
  fi

  # Check if the Sentinel2 product was retrieved, if not exit with the error code $ERR_NOINPUT
  [ $? -eq 0 ] && [ -e "${s2Product}" ] || return ${ERR_NOINPUT}

  s2ProductReference=$(basename "$s2Product" ".zip")
  
  outputDate=${s2ProductReference:45:8}
  outputName=$(printf "%s_%sZ_%s_CGS_V001_000" "${s2ProductReference:0:3}" "${s2ProductReference:45:15}" "${s2ProductReference:39:5}")
  outputNameNg=${outputName/CGS/NEXTGEOSS}

  # Call the Sentinel2 Biopar processing workflow for the given Sentinel2 product
  if [ $USE_STUB -eq 0 ]; then

      ciop-log "INFO" "Generating Sentinel2 Biopar product ${outputNameNg} (input = ${s2Product})"

      docker run                                                \
        -e "LD_LIBRARY_PATH=/home/worker/s2-biopar"             \
        -v ${inputDir}:/home/worker/workDir/inDir               \
        -v ${outputDir}:/home/worker/workDir/outDir             \
        -v ${tmpDir}:/home/worker/workDir/tmpDir                \
        vito-docker-private.artifactory.vgt.vito.be/nextgeoss-sentinel2-biopar:latest  \
        python /home/worker/s2-biopar/morpho_workflow.py -c /home/worker/s2-biopar/config/sentinel2_biopar_nextgeoss.ini --tmp_dir ${tmpDir} --delete_tmp /home/worker/workDir/inDir/$(basename $s2Product)

  else

      outDir="${outputDir}/${outputDate}/${outputName}"
      
      mkdir -p ${outDir}
      cp ${s2Product} ${outDir}

  fi

  # Check the exit code
  [ $? -eq 0 ] || return $ERR_BIOPAR

  # Create tarball of generated results
  ciop-log "INFO" "Creating tarball ${outputNameNg}.tgz"

  cd ${outputDir}/${outputDate}
  
  tar --transform='s/CGS/NEXTGEOSS/g' --show-transformed-names -czvf ${outputDir}/${outputNameNg}.tgz ${outputName}

  [ $? -eq 0 ] && [ -e "${outputDir}/${outputNameNg}.tgz" ] || return ${ERR_BIOPAR}

  cd -

  # Stage out the generated results to the next step
  ciop-publish ${outputDir}/${outputNameNg}.tgz
  
  [ $? -eq 0 ] || return ${ERR_PUBLISH}

  # Cleanup temporary results
  ciop-log "INFO" "Cleaning up temporary data"

  rm -rf ${s2Product} 
  docker run -v ${outputDir}:/home/worker/workDir/outDir vito-docker-private.artifactory.vgt.vito.be/nextgeoss-sentinel2-biopar:latest /bin/bash -c "rm -rf /home/worker/workDir/outDir/${outputNameNg}.tgz"
  docker run -v ${outputDir}:/home/worker/workDir/outDir vito-docker-private.artifactory.vgt.vito.be/nextgeoss-sentinel2-biopar:latest /bin/bash -c "rm -rf /home/worker/workDir/outDir/${outputDate}/${outputName}"
  docker run -v ${outputDir}:/home/worker/workDir/outDir vito-docker-private.artifactory.vgt.vito.be/nextgeoss-sentinel2-biopar:latest /bin/bash -c "rmdir  /home/worker/workDir/outDir/${outputDate} &> /dev/null"

  return ${SUCCESS}
}


