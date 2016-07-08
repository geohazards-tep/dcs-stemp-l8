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

  local geom=$1 
  local target=$2

  service="http://10.16.10.57:8080/wps/WebProcessingService" 

  wpsclient -a -u "${service}" -p "com.terradue.wps_oozie.process.OozieAbstractAlgorithm" -Iwkt="${geom}" -e -op ${target} &>/dev/null
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

  [ -z "$enclosure" ] && enclosure=$( url_resolver "${ref}" )
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
      
  local date=$1
  local station=$2
  local region=$3
  local target=$4

  # UTC format for date
  local year=${date:0:4}
  local month=${date:5:2}
  local day=${date:8:2}
  local hour=${date:11:2}

  if [ ${hour} -le "17" ]; then
    hour="00"
  else
    hour="12"
  fi

  local sounding_url="http://weather.uwyo.edu/cgi-bin/sounding?region=${region}&TYPE=TEXT%3ALIST&YEAR=${year}&MONTH=${month}&FROM=${day}${hour}&TO=${day}${hour}&STNM=${station}"

  curl -s -o ${target}/RAW${year}${month}${hour}_${station}.txt "${sounding_url}"
  res=$?
  [ ${res} -ne 0 ] && return ${res}

}

function url_resolver() {

  local url=""
  local reference="$1"
  
  read identifier path < <( opensearch-client -m EOP  "${reference}" identifier,wrsLongitudeGrid | tr "," " " )
  [ -z "${path}" ] && path="$( echo ${identifier} | cut -c 4-6)"
  row="$( echo ${identifier} | cut -c 7-9)"

  url="http://storage.googleapis.com/earthengine-public/landsat/L8/${path}/${row}/${identifier}.tar.bz"

  [ -z "$( curl -s --head "${url}" | head -n 1 | grep "HTTP/1.[01] [23].." )" ] && return 1

  echo "${url}"
}


