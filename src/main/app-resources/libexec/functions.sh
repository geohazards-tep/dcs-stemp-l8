#!/bin/bash
 
# source the ciop functions (e.g. ciop-log)
source ${ciop_job_include}

export PATH=/opt/anaconda/bin:/application/bin:$PATH 

SUCCESS=0
ERR_INVALID_MISSION=10
ERR_VOLCANO_NOT_FOUND=11
ERR_STATION_NOT_FOUND=12
ERR_GET_DATA=13
ERR_GET_DEM=14
ERR_GET_RAS=15
ERR_PUBLISH=255

# add a trap to exit gracefully
function cleanExit ()
{
  local retval=$?
  local msg=""
  case "$retval" in
    $SUCCESS)               msg="Processing successfully concluded";;
    $ERR_INVALID_MISSION)   msg="Invalid mission";;
    $ERR_VOLCANO_NOT_FOUND) msg="Volcano not found";;
    $ERR_STATION_NOT_FOUND) msg="Sounding station not found";;
    $ERR_GET_DATA)          msg="Error getting the input data";;
    $ERR_GET_DEM)           msg="Error getting the digital elevation model";;
    $ERR_GET_RAS)           msg="Error getting the athmosferic profile";;
    $ERR_PUBLISH)           msg="Failed results publish";;
    *)                      msg="Unknown error";;
  esac
  [ "$retval" != "0" ] && ciop-log "ERROR" "Error $retval - $msg, processing aborted" || ciop-log "INFO" "$msg"
  exit $retval
}

trap cleanExit EXIT

function getDem() {

  local ref=$1 
  local target=$2

  service="http://dem.terradue.int:8080/wps/WebProcessingService" 

  wpsclient -a -u "${service}" -p "com.terradue.wps_oozie.process.OozieAbstractAlgorithm" -ILevel0_ref="${ref}" -Iformat=roi_pac -e -op ${target} &>/dev/null
  res=$?
  [ ${res} -ne 0 ] && return ${res}
  
  metalink=$(cat ${target}/response.xml | xsltproc /usr/lib/ciop/xsl/wps2meta.xsl - | sed 's#\(.*OPEN\).*#\1#g')

  xsltproc /usr/lib/ciop/xsl/meta2url.xsl ${metalink} | while read link; do
    echo ${link} | tr -d '\r' | ciop-copy -O $target -
  done

}

function getData() {
 
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

function getRas() {

  local station=$1
  local date=$2 
  local target=$3
  return 0

}
