#!/bin/bash

source /application/libexec/functions.sh

function get_data() {
  local ref=$1
  local target=$2
  local local_file
  local enclosure
  local res

  [ "${ref:0:4}" == "file" ] || [ "${ref:0:1}" == "/" ] && enclosure=${ref}

  [ -z "$enclosure" ] && enclosure=$( opensearch-client "${ref}" enclosure ) 
  res=$?
  enclosure=$( echo ${enclosure} | tail -1 )
  [ $res -eq 0 ] && [ -z "${enclosure}" ] && return ${ERR_GETDATA}
  [ $res -ne 0 ] && enclosure=${ref}

  local_file="$( echo ${enclosure} | ciop-copy -f -U -O ${target} - 2> /dev/null )"
  res=$?
  [ ${res} -ne 0 ] && return ${res}
  echo ${local_file}
}


function main() {

  # prepare STEMP environment
  
  # stage-in inputs
  # input_file=$( get_data ${1} ${TMPDIR}/PROCESSING )
  
  #esport IDL variable
  export LM_LICENSE_FILE=1700@idl.terradue.int
  export MODTRAN_BIN=/opt/MODTRAN-5.4.0/
  # temporary PROCESSING_HOME fixed
  export PROCESSING_HOME=/data/code/PROCESSING/
#  export PROCESSING_HOME=${TMPDIR}/PROCESSING
#  mkdir -p ${PROCESSING_HOME}

  # temporary
#  cp /data/code/PROCESSING/file_input.cfg ${PROCESSING_HOME}
  # invoke the app with the local staged data
  STEMP_BIN=/data/code/STEMP-1.0
  /usr/local/bin/idl -rt=${STEMP_BIN}/STEMP.sav

  # create quicklooks
  cd ${PROCESSING_HOME}
  string_inp=$(head -n 1 file_input.cfg)
  leng=${#string_inp}
  gdal_translate -scale -10 10 0 255 -ot Byte -of PNG ${string_inp:0:leng-4}_TEMP.tif ${string_inp:0:leng-4}_TEMP.png
  listgeo -tfw ${string_inp:0:leng-4}_TEMP.tif
  mv ${string_inp:0:leng-4}_TEMP.tfw ${string_inp:0:leng-4}_TEMP.pngw

  
  # stage-out the results
  ciop-publish -m /data/code/PROCESSING/*TEMP.tif || return $?
  ciop-publish -m /data/code/PROCESSING/*TEMP.png* || return $?
}


while read input
do
    main ${input}
    res=$?
    [ "${res}" != "0" ] && exit ${res}
done

exit ${SUCCESS}
