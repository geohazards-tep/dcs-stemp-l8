#!/bin/bash

source /application/libexec/functions.sh

export DB_PATH=${_CIOP_APPLICATION_PATH}/query/db
export PATH=${_CIOP_APPLICATION_PATH}/query/bin:$PATH

function find_station() {
  
  v_lon=$1
  v_lat=$2

  # simple searching function, it could be improved in performance
  cat ${DB_PATH}/sounding_stations | while IFS=',' read region station_id s_lon s_lat
  do
    dist=$( haversine.py $v_lon $v_lat $s_lon $s_lat )

    [ -z ${dist_old} ] && dist_old=${dist}
   
    [ "$( echo ${dist} '>' ${dist_old} | bc -l )" == "0" ] && { 
      echo ${region} ${station_id} > station_found
      dist_old=${dist}
    }
  done

  cat station_found
  rm -f station_found
}

function main() {

  local startdate="$(ciop-getparam startdate)"
  local enddate="$(ciop-getparam enddate)"
  local volcano="$(ciop-getparam volcano)"
  local mission="$(ciop-getparam mission)"

  [ -z ${startdate} ] && exit $ERR_PARAM
  [ -z ${enddate} ] && exit $ERR_PARAM
 
  IFS=',' read volcano v_lon v_lat station region < <( cat ${DB_PATH}/volcanoes | grep "${volcano,,}" )
  [ -z "${volcano}" ] && exit $ERR_VOLCANO_NOT_FOUND

  ciop-log "INFO" "Volcano name: ${volcano}"
  ciop-log "INFO" "Volcano coordinates: ${v_lon} ${v_lat}"
  
  local geom="POINT(${v_lon} ${v_lat})"

  if [ -z "${station}" ]; then
    station_found=$( find_station ${v_lon} ${v_lat} )
    [ -z "${station_found}" ] && exit $ERR_STATION_NOT_FOUND
    region=$( echo ${station_found} | cut -d ' ' -f1 )
    station=$( echo ${station_found} | cut -d ' ' -f2 )
  fi

  ciop-log "INFO" "Nearest atmosferic station: ${station},${region}"
  ciop-log "INFO" "Geometry in WKT: ${geom}"

  ciop-log "INFO" "Opensearch query: opensearch-client -p \"start=${startdate}\" -p \"stop=${enddate}\" \"https://data2.terradue.com/eop/${mission,,}/dataset/search?geom=${geom}\""
 
  opensearch-client \
    -p "start=${startdate}" \
    -p "stop=${enddate}" \
    "https://data2.terradue.com/eop/${mission,,}/dataset/search?geom=${geom}" \
    self,identifier,enddate | tr "," " " > ${TMPDIR}/opensearch_response.txt
  res=$?
  [ ${res} -ne 0 ] && return ${ERR_GET_DATA}
  
  count=$( wc -l < ${TMPDIR}/opensearch_response.txt )
  
  if [ ${count} -gt 0 ]; then
      
    cat ${TMPDIR}/opensearch_response.txt | while read self identifier enddate
    do
      ciop-log "INFO" "Publishing to the stemp node: ${self},${identifier},${mission,,},${enddate},${station},${region},${volcano},${geom}"
      echo "${self},${identifier},${mission,,},${enddate},${station},${region},${volcano},${geom}" | ciop-publish -s
    done
    
  else
    return ${ERR_DATA_NOT_FOUND}
  fi

} 

# the dummy input here is a workaround for this particular query step of the
# STEMP application
while read dummy
do
   main || exit $?
done

exit ${SUCCESS}
