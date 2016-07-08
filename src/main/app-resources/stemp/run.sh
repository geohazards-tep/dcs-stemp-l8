#!/bin/bash

source /application/libexec/functions.sh

export LM_LICENSE_FILE=1700@idl.terradue.int
export MODTRAN_BIN=/opt/MODTRAN-5.4.0
export STEMP_BIN=/data/code/STEMP-1.0
export PROCESSING_HOME=${TMPDIR}/PROCESSING

function main() {

  local product=$1
  local date=$2
  local station=$3
  local region=$4
  local geom=$5

  # preparing STEMP environment
  export PROCESSING_HOME=${TMPDIR}/PROCESSING
  mkdir -p ${PROCESSING_HOME}
  ln -sf /opt/MODTRAN-5.4.0/Mod5.4.0tag/DATA ${PROCESSING_HOME}/DATA

  ciop-log "INFO" "Input product reference: ${product}" 
  ciop-log "INFO" "Date and time: ${date}" 
  ciop-log "INFO" "Reference atmospheric station: ${station}" 
  ciop-log "INFO" "Reference region: ${region}" 
  ciop-log "INFO" "Geometry in WKT format: ${geom}" 
 
  ciop-log "INFO" "Getting atmospheric profile ..." 
  getRas ${date} ${station} ${region} ${PROCESSING_HOME}
  res=$?
  [ ${res} -ne 0 ] && return ${ERR_GET_RAS}
  
  ciop-log "INFO" "Getting digital elevation model ..." 
  getDem ${product} ${PROCESSING_HOME}
  res=$?
  [ ${res} -ne 0 ] && return ${ERR_GET_DEM}
  
  ciop-log "INFO" "Getting input product ..." 
  getData ${product} ${PROCESSING_HOME}
  res=$?
  [ ${res} -ne 0 ] && return ${ERR_GET_DATA}

  ls -l ${PROCESSING_HOME}

  exit 0

  # temporary
#  cp /data/code/PROCESSING/file_input.cfg ${PROCESSING_HOME}
  ciop-log "INFO" "Starting STEMP ..." 
  /usr/local/bin/idl -rt=${STEMP_BIN}/STEMP.sav

  # create quicklooks
  cd ${PROCESSING_HOME}
  string_inp=$(head -n 1 file_input.cfg)
  leng=${#string_inp}
  gdal_translate -scale -10 10 0 255 -ot Byte -of PNG ${string_inp:0:leng-4}_TEMP.tif ${string_inp:0:leng-4}_TEMP.png
  listgeo -tfw ${string_inp:0:leng-4}_TEMP.tif
  mv ${string_inp:0:leng-4}_TEMP.tfw ${string_inp:0:leng-4}_TEMP.pngw
  
  # stage-out the results
  ciop-publish -m ${PROCESSING_HOME}/*TEMP.tif || return $?
  ciop-publish -m ${PROCESSING_HOME}/*TEMP.png* || return $?
}

while IFS=',' read product date station region geom
do
    main ${product} ${date} ${station} ${region} ${geom}
    res=$?
    [ "${res}" != "0" ] && exit ${res}
done

exit ${SUCCESS}
