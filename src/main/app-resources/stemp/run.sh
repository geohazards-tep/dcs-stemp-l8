#!/bin/bash

source /application/libexec/functions.sh

export LM_LICENSE_FILE=1700@idl.terradue.int
export MODTRAN_BIN=/opt/MODTRAN-5.4.0
export STEMP_BIN=/data/code/STEMP-1.0
export PROCESSING_HOME=${TMPDIR}/PROCESSING

function main() {

  local ref=$1
  local identifier=$2
  local date=$3
  local station=$4
  local region=$5
  local volcano=$6
  local geom=$7

  ciop-log "INFO" "**** STEMP node ****"
  ciop-log "INFO" "------------------------------------------------------------"
  ciop-log "INFO" "Input product reference: ${ref}" 
  ciop-log "INFO" "Date and time: ${date}" 
  ciop-log "INFO" "Reference atmospheric station: ${station}, ${region}" 
  ciop-log "INFO" "Volcano name: ${volcano}" 
  ciop-log "INFO" "Geometry in WKT format: ${geom}"
  ciop-log "INFO" "------------------------------------------------------------"
  
  ciop-log "INFO" "Preparing the STEMP environment"
  export PROCESSING_HOME=${TMPDIR}/PROCESSING
  mkdir -p ${PROCESSING_HOME}
  ln -sf /opt/MODTRAN-5.4.0/Mod5.4.0tag/DATA ${PROCESSING_HOME}/DATA
 
  ciop-log "INFO" "Getting atmospheric profile" 
  local profile=$( getRas "${date}" "${station}" "${region}" "${PROCESSING_HOME}")
  res=$?
  [ "${res}" -ne "0" ] && return ${ERR_GET_RAS}
  ciop-log "INFO" "Atmospheric profile downloaded" 
  ciop-log "INFO" "------------------------------------------------------------"
  
  ciop-log "INFO" "Getting Digital Elevation Model" 
  local dem=$( getDem "${geom}" "${PROCESSING_HOME}" )
  res=$?
  [ "${res}" -ne "0" ] && return ${ERR_GET_DEM}
  ciop-log "INFO" "Digital Elevation Model downloaded"
  ciop-log "INFO" "------------------------------------------------------------" 
  
  ciop-log "INFO" "Getting input product" 
  local product=$( getData "${ref}" "${PROCESSING_HOME}" )
  res=$?
  [ "${res}" -ne "0" ] && return ${ERR_GET_DATA}
  ciop-log "INFO" "Input product downloaded"
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Uncompressing product" 
  
  case ${product##*.} in
    zip)
      unzip -qq -o ${product} -d ${PROCESSING_HOME}
    ;;
    
    gz)
      tar xzf ${product} -C ${PROCESSING_HOME}
    ;;
    
    bz2 | bz)
      tar xjf ${product} -C ${PROCESSING_HOME}
    ;;
    *)
      ciop-log "ERROR" "Unsupported "${product##*.}" format"
      return ${$ERR_UNCOMP}
    ;;
  esac
   
  res=$?
  [ "${res}" -ne "0" ] && return ${$ERR_UNCOMP}
  ciop-log "INFO" "Product uncompressed"
  ciop-log "INFO" "------------------------------------------------------------"
 
  ciop-log "INFO" "Preparing file_input.cfg" 
  echo "$( basename ${identifier})_B10.TIF" >> ${PROCESSING_HOME}/file_input.cfg
  basename ${profile} >> ${PROCESSING_HOME}/file_input.cfg
  basename ${dem} >> ${PROCESSING_HOME}/file_input.cfg
  basename ${volcano} >> ${PROCESSING_HOME}/file_input.cfg

  ciop-log "INFO" "file_input.cfg content:"
  cat ${PROCESSING_HOME}/file_input.cfg 1>&2
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "PROCESSING_HOME content:"
  ls -l ${PROCESSING_HOME} 1>&2
  
  ciop-log "INFO" "STEMP environment ready"
  ciop-log "INFO" "------------------------------------------------------------"

  # temporary stopping the process
  exit ${SUCCESS}

  ciop-log "INFO" "Starting STEMP core"
  /usr/local/bin/idl -rt=${STEMP_BIN}/STEMP.sav -IDL_DEVICE Z  
  
  ciop-log "INFO" "STEMP core finished"
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Generating quicklooks"
  
  cd ${PROCESSING_HOME}
  string_inp=$(head -n 1 file_input.cfg)
  leng=${#string_inp}
  gdal_translate -scale -10 10 0 255 -ot Byte -of PNG ${string_inp:0:leng-4}_TEMP.tif ${string_inp:0:leng-4}_TEMP.png
  listgeo -tfw ${string_inp:0:leng-4}_TEMP.tif
  mv ${string_inp:0:leng-4}_TEMP.tfw ${string_inp:0:leng-4}_TEMP.pngw
  
  ciop-log "INFO" "Quicklooks generated:"
  ls -l ${PROCESSING_HOME}/*TEMP.png* 1>&2
  ciop-log "INFO" "------------------------------------------------------------"
  
  ciop-log "INFO" "Staging-out results ..."
  ciop-publish -m ${PROCESSING_HOME}/*TEMP.tif || return $?
  ciop-publish -m ${PROCESSING_HOME}/*TEMP.png* || return $?
  [ "${res}" -ne "0" ] && return ${ERR_PUBLISH}
  
  ciop-log "INFO" "Results staged out"
  ciop-log "INFO" "------------------------------------------------------------"
  
  ciop-log "INFO" "Cleaning STEMP environment"
  rm -rf ${PROCESSING_HOME}/*
  ciop-log "INFO" "------------------------------------------------------------"
  ciop-log "INFO" "**** STEMP node finished ****"
}

while IFS=',' read ref identifier date station region volcano geom
do
    main "${ref}" "${identifier}" "${date}" "${station}" "${region}" "${volcano}" "${geom}"
    res=$?
    [ "${res}" != "0" ] && exit ${res}
done

exit ${SUCCESS}
