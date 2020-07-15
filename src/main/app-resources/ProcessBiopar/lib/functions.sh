#!/bin/bash

# define the exit codes
SUCCESS=0
ERR_NOINPUT=50
ERR_BIOPAR=51
ERR_PUBLISH=52
ERR_FILTER=53

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
    ${ERR_FILTER})  msg="Failed to filter the Sentinel2 product";;
    *) msg="Unknown error";;
  esac

  ciop-log "INFO" "Cleaning up tmp folder"
  rm -rf ${TMPDIR}/s2-biopar-tmp
 
  [ "${retval}" != "0" ] && ciop-log "ERROR" "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  exit ${retval}
}

###############################################################################
# Functions to retrieve the opensearch mapping
###############################################################################
function getosparams() {
        URL=$1
        PARAMS=${URL##*\?}
        PARAMS_ARR=(${PARAMS//[&]/ })
        declare -A PARAM_MAPPING
        PARAM_MAPPING['identifier']="{http://a9.com/-/opensearch/extensions/geo/1.0/}uid"
        PARAM_MAPPING['timerange_start']="{http://a9.com/-/opensearch/extensions/time/1.0/}start"
        PARAM_MAPPING['timerange_end']="{http://a9.com/-/opensearch/extensions/time/1.0/}end"
        PARAM_MAPPING['bbox']="{http://a9.com/-/opensearch/extensions/geo/1.0/}box"
        PARAM_MAPPING['count']="{http://a9.com/-/spec/opensearch/1.1/}count"

        COMMAND_PARAMS=""
        for param in "${PARAMS_ARR[@]}"
        do
                p=(${param//[=]/ })

                if [[ ! -z ${PARAM_MAPPING[${p[0]}]} ]]; then
                        COMMAND_PARAMS+=" -p ${PARAM_MAPPING[${p[0]}]}=${p[1]}"
                fi
        done
        echo $COMMAND_PARAMS

}

###############################################################################
# Main function to generate bio-physical parameters from a given Sentinel2
# product reference.
###############################################################################
function main()
{
  local input=${1}

  ciop-log "INFO" "Received input Sentinel2 product ${input}"

  # Setup some folder to store the Sentinel2 products
  
  local inputDir=${TMPDIR}/s2-biopar-input
  local outputDir=${TMPDIR}/s2-biopar-output
  local tmpDir=${TMPDIR}/s2-biopar-tmp

  #local inputDir="/home/worker/workDir/inDir" 
  #local outputDir="/home/worker/workDir/outDir" 
  #local tmpDir="/home/worker/workDir/tmpDir"
 
  mkdir -p ${inputDir}
  mkdir -p ${outputDir}
  mkdir -p ${tmpDir}

  # Retrieve job specific parameters
  SENTINEL2_TILES="`ciop-getparam s2tiles`"

  ciop-log "INFO" "Sentinel2 tiles to be processed = ${SENTINEL2_TILES}"

  # Stage in the input file to a temporary folder that is unique for this workflow ($TMPDIR)

  if [[ ${input:0:4} == "file" ]]; then
      enclosure=${input}
  else
      # Escape (,) characters to prevent error in opensearch client
      params=$(getosparams $input)
      ciop-log "INFO" "Querying opensearch client with params $params"
      enclosure="$(opensearch-client $params https://catalogue-lite.nextgeoss.eu/opensearch/description.xml?osdd=SENTINEL2_L1C enclosure)"
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

  # Retrieve meta-data information from the product

  ciop-log "INFO" "Retrieving metadata of Sentinel2 product ${s2ProductReference}"

  # Get satellite identifier (i.e. S2A, S2B, ...)
  s2Id=${s2ProductReference:0:3}

  # Get timestamp and tile identifiers
  s2TileIdentifiers=()

  if [[ $s2ProductReference =~ S2._OPER_PRD_MSIL1C_PDMC_.* ]]; then

     # Example: S2A_OPER_PRD_MSIL1C_PDMC_20160102T180344_R051_V20160102T110129_20160102T110129.zip

     s2ProductDate=${s2ProductReference:47:8}
     s2ProductDateTime=${s2ProductReference:47:15}

     extension="${input##*.}"

     if [ "$extension" == "zip" ]; then

       res=`unzip -l ${s2Product} | grep ".*GRANULE.*xml" | awk '{print $4}'`

       for f in $res; do

           f=$(basename "$f" ".xml")
           s2TileIdentifiers+=(${f:50:5})

       done

     elif [ "$extension" == "SAFE" ]; then

       res=`ls ${s2Product}/GRANULE`

       for f in $res; do

           f=$(basename "$f")
           s2TileIdentifiers+=(${f:50:5})

       done

     fi

  else

     # Example: S2A_MSIL1C_20161211T103432_N0204_R108_T32ULA_20161211T103426.zip

     s2ProductDate=${s2ProductReference:11:8}
     s2ProductDateTime=${s2ProductReference:11:15}
     s2TileIdentifiers+=(${s2ProductReference:39:5})

  fi

  ciop-log "INFO" "Sentinel2 ID = $s2Id"
  ciop-log "INFO" "Sentinel2 Product Date = $s2ProductDate"
  ciop-log "INFO" "Sentinel2 Product DateTime = $s2ProductDateTime"

  for tile in "${s2TileIdentifiers[@]}"; do
        ciop-log "INFO" "Sentinel2 Tile = ${tile}"
  done

  # Filter the tiles from the input product and create temporary zip file
  ciop-log "INFO" "Filtering tiles of Sentinel2 product ${s2ProductReference}"

  s2ProductInput="/home/worker/workDir/inDir/$(basename ${s2Product})"
  s2ProductFiltered="/home/worker/workDir/tmpDir/$(basename ${s2Product})"
  s2ProductFilteredPath="${tmpDir}/$(basename ${s2Product})"
  ciop-log "INFO" "Triggering docker with ${s2ProductInput} ${s2ProductFiltered} ${SENTINEL2_TILES}"

  docker run --rm                                                                       \
        -v ${inputDir}:/home/worker/workDir/inDir                                       \
        -v ${outputDir}:/home/worker/workDir/outDir                                     \
        -v ${tmpDir}:/home/worker/workDir/tmpDir                                        \
        vito-docker-private.artifactory.vgt.vito.be/nextgeoss-sentinel2-biopar:latest   \
        python /home/worker/s2-biopar/sentinel2_tile_filter.py ${s2ProductInput} ${s2ProductFiltered} ${SENTINEL2_TILES}

  echo "PRODUCT CHECK ${s2ProductFilteredPath}"
  ls -l ${s2ProductFilteredPath}
 
  # Check the exit code
  # [ $? -eq 0 ] || return $ERR_FILTER
  [ -f "${s2ProductFilteredPath}" ] || return $ERR_FILTER

  # Call the Sentinel2 Biopar processing workflow for the given Sentinel2 product

  ciop-log "INFO" "Creating bio-physical parameters of Sentinel2 product ${s2ProductReference}"

  # tmpDir=${TMPDIR}/s2-biopar-tmp/${s2ProductReference}/tmp
  ciop-log "INFO" "Setting tmp dir to ${tmpDir}"
  
  outputDir=${TMPDIR}/s2-biopar-output/${s2ProductReference}/out
  ciop-log "INFO" "Setting output dir to ${outputDir}"

  echo "${s2ProductFiltered}"
  echo "${inputDir}"
  ls -l ${inputDir}  
  docker run --rm                                                                       \
        -e "LD_LIBRARY_PATH=/home/worker/s2-biopar"                                     \
        -v ${inputDir}:/home/worker/workDir/inDir                                       \
        -v ${outputDir}:/home/worker/workDir/outDir                                     \
        -v ${tmpDir}:/home/worker/workDir/tmpDir                                        \
        vito-docker-private.artifactory.vgt.vito.be/nextgeoss-sentinel2-biopar:latest   \
        python /home/worker/s2-biopar/morpho_workflow.py -c /home/worker/s2-biopar/config/sentinel2_biopar_nextgeoss.ini --tmp_dir /home/worker/workDir/tmpDir  --delete_tmp ${s2ProductFiltered}

  # Check the exit code
  [ $? -eq 0 ] || return $ERR_BIOPAR

  echo "CHECKING OUTPUT DIR ${outputDir}"
  ls -l ${outputDir}
  ls -l ${outputDir}/*

  # Publish results to next processing step
  for s2TileId in "${s2TileIdentifiers[@]}"; do

      search=$(printf "%s_%s.*_%s_CGS_V001_000" "${s2Id}" "${s2ProductDate}" "${s2TileId}")
      outputName=$(ls -t ${outputDir}/${s2ProductDate} | grep ${search} | head -n 1)
      outputNameNg=${outputName/CGS/NEXTGEOSS}


      # Check whether the tile has been generated
      if [ ! -d "${outputDir}/${s2ProductDate}/${outputName}" ]; then
          continue
      fi

      ciop-log "INFO" "Publishing Sentinel2 Biopar product ${outputNameNg}"


      ciop-log "INFO" "Updating permissions for ${outputName}"

      docker run -v ${outputDir}:/home/worker/workDir/outDir vito-docker-private.artifactory.vgt.vito.be/nextgeoss-sentinel2-biopar:latest /bin/bash -c "chmod -R 777 /home/worker/workDir/outDir/"
  
      # Create tarball of generated results
      ciop-log "INFO" "Creating tarball ${outputNameNg}.tgz"

      cd ${outputDir}/${s2ProductDate}
   
      tar --transform='s/CGS/NEXTGEOSS/g' --show-transformed-names -czvf ${outputDir}/${outputNameNg}.tgz ${outputName}

      [ $? -eq 0 ] && [ -e "${outputDir}/${outputNameNg}.tgz" ] || return ${ERR_BIOPAR}

      cd -

      # Stage out the generated results to the next step
      ciop-publish ${outputDir}/${outputNameNg}.tgz
      
      [ $? -eq 0 ] || return ${ERR_PUBLISH}

      # Cleanup temporary results
      ciop-log "INFO" "Cleaning up temporary data"
      
      docker run -v ${outputDir}:/home/worker/workDir/outDir vito-docker-private.artifactory.vgt.vito.be/nextgeoss-sentinel2-biopar:latest /bin/bash -c "rm -rf /home/worker/workDir/outDir/${outputNameNg}.tgz"
      docker run -v ${outputDir}:/home/worker/workDir/outDir vito-docker-private.artifactory.vgt.vito.be/nextgeoss-sentinel2-biopar:latest /bin/bash -c "rm -rf /home/worker/workDir/outDir/${s2ProductDate}/${outputName}"
      docker run -v ${outputDir}:/home/worker/workDir/outDir vito-docker-private.artifactory.vgt.vito.be/nextgeoss-sentinel2-biopar:latest /bin/bash -c "rmdir  /home/worker/workDir/outDir/${s2ProductDate} &> /dev/null"

  done

  # Cleanup temporary data
  docker run -v ${tmpDir}:/home/worker/workDir/tmpDir vito-docker-private.artifactory.vgt.vito.be/nextgeoss-sentinel2-biopar:latest /bin/bash -c "rm -rf ${s2ProductFiltered}"

  # Cleanup input product
  rm -rf ${s2Product}

  return ${SUCCESS}
}


