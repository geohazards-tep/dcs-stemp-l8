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

  # preparing STEMP environment
  # temporary
  PROCESSING_HOME=/data/code/PROCESSING/
  mkdir -p ${PROCESSING_HOME}

  ciop-log "INFO" "Input product reference: ${product}" 
  ciop-log "INFO" "Date and time: ${date}" 
  ciop-log "INFO" "Reference atmospheric station: ${station}" 
 
  ciop-log "INFO" "Getting atmospheric profile ..." 
  getRas ${station} ${date} ${PROCESSING_HOME}
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

  # temporary
#  cp /data/code/PROCESSING/file_input.cfg ${PROCESSING_HOME}
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

while IFS=',' read product date station
do
    main ${product} ${date} ${station}
    res=$?
    [ "${res}" != "0" ] && exit ${res}
done

exit ${SUCCESS}
