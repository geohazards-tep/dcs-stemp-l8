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
ERR_CONV_DEM=16
ERR_CROP_DEM=17
ERR_DATA_NOT_FOUND=18
ERR_UNCOMP=254
ERR_PUBLISH=255

# add a trap to exit gracefully
function cleanExit () {
  
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
    $ERR_DATA_NOT_FOUND)    msg="Data not found on the Catalogue";;
    $ERR_UNCOMP)            msg="Failed uncompressing product";;
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

  endpoint="http://dem-90m-wkt.platform.terradue.int:8080/wps/WebProcessingService" 

  ciop-log "INFO" "[getDem function] DEM WPS service endpoint: ${endpoint} "
  ciop-log "INFO" "[getDem function] WTK input: ${geom} "
  ciop-log "INFO" "[getDem function] Starting DEM WPS remote service"
 
  wpsclient -a -u "${endpoint}" -p "com.terradue.wps_oozie.process.OozieAbstractAlgorithm" -Iwkt="${geom}" -e -op ${target} &>/dev/null
  res=$?

  ciop-log "INFO" "[getDem function] DEM WPS request completed with return code: ${res}"
  
  [ ${res} -ne 0 ] && return ${res}
  
  ciop-log "INFO" "[getDem function] Extracting metalink"
  
  metalink=$(cat ${target}/response.xml | xsltproc /usr/lib/ciop/xsl/wps2meta.xsl - | sed 's#\(.*OPEN\).*#\1#g')

  ciop-log "INFO" "[getDem function] Metalink: ${metalink}"
  
  xsltproc /usr/lib/ciop/xsl/meta2url.xsl ${metalink} | while read link; do
    echo ${link} | tr -d '\r' | ciop-copy -O $target -
  done

}

function generateQuicklook() {

  input=${1}
  target=${2}
  basename=$( basename ${input} )
  filename=${basename%.*}

  /opt/anaconda/bin/gdal_translate -a_nodata 0 -scale -10 80 0 255 -of VRT ${input} ${target}/${filename}.vrt

  xmlstarlet ed -L -u '/VRTDataset/VRTRasterBand/ColorInterp' -v "Palette" ${target}/${filename}.vrt
  xmlstarlet ed -L -s '/VRTDataset/VRTRasterBand' -t elem -n "ColorTable" -v "" ${target}/${filename}.vrt

  cat ${_CIOP_APPLICATION_PATH}/aux/Palette/heat4.txt | while read r g b a
  do
    xmlstarlet ed -L -s '/VRTDataset/VRTRasterBand/ColorTable' -t elem -n 'EntryTMP' -v '' \
       -i '/VRTDataset/VRTRasterBand/ColorTable/EntryTMP' -t attr -n c1 -v "${r}" \
       -i '/VRTDataset/VRTRasterBand/ColorTable/EntryTMP' -t attr -n c2 -v "${g}" \
       -i '/VRTDataset/VRTRasterBand/ColorTable/EntryTMP' -t attr -n c3 -v "${b}" \
       -i '/VRTDataset/VRTRasterBand/ColorTable/EntryTMP' -t attr -n c4 -v "${a}" \
       -r '/VRTDataset/VRTRasterBand/ColorTable/EntryTMP' -v 'Entry' ${target}/${filename}.vrt
  done

  /opt/anaconda/bin/gdal_translate -of PNG -ot Byte ${target}/${filename}.vrt ${target}/${filename}.png 1>&2

  listgeo -tfw ${input}
  mv ${target}/${filename}.tfw ${target}/${filename}.pngw
}

function convertDemToGeoTIFF() {

  local rsc=$1
  local dem=$2
  local target=$3

  ciop-log "INFO" "[convertDemToGeoTIFF function] GeoTIFF conversion: ${utm_zone}"
  ciop-log "INFO" "[convertDemToGeoTIFF function] Preparing ENVI .hdr Labelled Raster"
  
  X_FIRST=$( sed -n 's#^X_FIRST\s*\(.*\)$#\1#p' ${rsc} )
  Y_FIRST=$( sed -n 's#^Y_FIRST\s*\(.*\)$#\1#p' ${rsc} )
  X_STEP=$( sed -n 's#^X_STEP\s*\(.*\)$#\1#p' ${rsc} )
  WIDTH=$( sed -n 's#^WIDTH\s*\(.*\)$#\1#p' ${rsc} )
  FILE_LENGTH=$( sed -n 's#^FILE_LENGTH\s*\(.*\)$#\1#p' ${rsc} )

  X_STEP=$( echo "define abs(x) {if (x<0) {return -x}; return x;}; abs(${X_STEP})" | bc )
  X_STEP=$( printf '%.15f\n' ${X_STEP} )
  
cat << EOF > ${target}/dem.hdr
ENVI
description = {
dem}
samples = ${WIDTH}
lines   = ${FILE_LENGTH}
bands   = 1
header offset = 0
file type = ENVI Standard
data type = 2
interleave = bsq
byte order = 0
map info = {Geographic Lat/Lon, 1, 1, ${X_FIRST%.*}, ${Y_FIRST%.*}, ${X_STEP}, ${X_STEP}, WGS-84}
band names = {
dem}
EOF

  ciop-log "INFO" "[convertDemToGeoTIFF function] .hdr Raster:"
  cat ${target}/dem.hdr 1>&2
  
  ciop-log "INFO" "gdal_translate ${dem} ${target}/dem.TIF"
  
  gdal_translate ${dem} ${target}/dem.TIF 1>&2
  
  echo ${target}/dem.TIF
}

function cropDem() {
  
  local dem=$1
  local target=$2
  local lon=$3
  local lat=$4
  local extent=$5
  
  ciop-log "INFO" "[cropDem function] lon: ${lon}"
  ciop-log "INFO" "[cropDem function] lat: ${lat}"
  ciop-log "INFO" "[cropDem function] extent: ${extent}"

  local west=$( echo "${lon} - ${extent}" | bc )
  local north=$( echo "${lat} + ${extent}" | bc )
  local east=$( echo "${lon} + ${extent}" | bc )
  local south=$( echo "${lat} - ${extent}" | bc )
  
  ciop-log "INFO" "[cropDem function] west: ${west}"
  ciop-log "INFO" "[cropDem function] north: ${north}"
  ciop-log "INFO" "[cropDem function] east: ${east}"
  ciop-log "INFO" "[cropDem function] south: ${south}"

  gdal_translate -of GTiff -projwin ${west} ${north} ${east} ${south} ${dem} ${target}/dem_crop.TIF 1>&2
  
  echo ${target}/dem_crop.TIF
}


function getData() {
 
  local ref=$1
  local target=$2
  local local_file
  local enclosure
  local res

  if [ "${ref:0:4}" == "file" ] || [ "${ref:0:1}" == "/" ]; then
    enclosure=${ref}
  else
    enclosure=$( urlResolver "${ref}" )
    res=$?
    [ "${res}" -ne "0" ] && ${ERR_GETDATA}
  fi

  ciop-log "INFO" "[getData function] Data enclosure url: ${enclosure}"
  
  local_file="$( echo ${enclosure} | ciop-copy -f -U -O ${target} - 2> /dev/null )"
  res=$?
  [ "${res}" -ne "0" ] && return ${ERR_GETDATA}
  
  echo ${local_file}
}

function getRas() {
      
  local date=$1
  local station=$2
  local region=$3
  local target=$4
  local days=0
  local MAX_DAYS_BEFORE=10

  # UTC format for date
  local year=${date:0:4}
  local month=${date:5:2}
  local day=${date:8:2}
  local hour=${date:11:2}
  
  ref_date="${year}-${month}-${day}"
 
  # Implementing rule defined at https://support.terradue.com/issues/4434
  if [ ${hour} -le 5 ]; then
    hour="00"
  else
    if [ ${hour} -le 17 ]; then
      hour="12"
    else
      hour="00"
      ref_date=$(date -d "${ref_date} +1 day" '+%Y-%m-%d')
      ciop-log "INFO" "[getRas function] Since hour is greater than 17:59, we get the atmospheric profile of the day after at ${hour}"
    fi
  fi
  
  local terminate=0

  while [ ${terminate} -eq 0 ] ; do
    
    local new_date=$(date -d "${ref_date} -${days} day" '+%Y-%m-%d')
    
    year=${new_date:0:4}
    month=${new_date:5:2}
    day=${new_date:8:2}
    
    if [ ${days} -gt 0 ]; then
      ciop-log "INFO" "[getRas function] Trying to get atmospheric profile ${days} day(s) before"
    fi
    
    local sounding_url="http://weather.uwyo.edu/cgi-bin/sounding?region=${region}&TYPE=TEXT%3ALIST&YEAR=${year}&MONTH=${month}&FROM=${day}${hour}&TO=${day}${hour}&STNM=${station}"

    ciop-log "INFO" "[getRas function] sounding url: ${sounding_url} "

    curl -s -o ${TMPDIR}/RAW${year}${month}${day}${hour}_${station}.txt "${sounding_url}"
    curl_res=$?
    
    ciop-log "INFO" "[getRas function] curl request return code: ${curl_res}"
    
    ciop-log "INFO" "[getRas function] Checking if the atmospheric profile is valid (i.e., it doesn't contain the words \"Can't get\")..."
    
    grep "Can't get" ${TMPDIR}/RAW${year}${month}${day}${hour}_${station}.txt > /dev/null 2>&1
    grep_res=$?

    if [ ${curl_res} -ne 0 ] || [ ${grep_res} -eq 0 ] ; then
      days=$((days+1))
      if [ ${days} -gt ${MAX_DAYS_BEFORE} ] ; then
        terminate=1
        cp ${_CIOP_APPLICATION_PATH}/aux/RAS/${region}.txt ${target}/
        
        ciop-log "INFO" "[getRas function] Provided default atmospheric profile: ${_CIOP_APPLICATION_PATH}/aux/RAS/${region}.txt"
        echo "${target}/${region}.txt"
      fi
    else
      terminate=1
      cp ${TMPDIR}/RAW${year}${month}${day}${hour}_${station}.txt ${target}/

      echo "${target}/RAW${year}${month}${day}${hour}_${station}.txt"
    fi
  done
}

function urlResolver() {

  local url=""
  local reference="$1"
  
  # Managing the special case for Landsat8, where we get data directly from
  # Google
  landsat8=$( echo "${reference}" | grep "landsat8" )
  
  if [ -n "${landsat8}" ]; then
    read identifier path < <( opensearch-client -m EOP  "${reference}" identifier,wrsLongitudeGrid | tr "," " " )
    [ -z "${path}" ] && path="$( echo ${identifier} | cut -c 4-6)"
    row="$( echo ${identifier} | cut -c 7-9)"

    url="http://storage.googleapis.com/earthengine-public/landsat/L8/${path}/${row}/${identifier}.tar.bz"
    [ -z "$( curl -s --head "${url}" | head -n 1 | grep "HTTP/1.[01] [23].." )" ] && return 1

    echo "${url}"
  else
    url=$( opensearch-client "${reference}" enclosure )
    res=$?
    [ "${res}" -ne "0" ] && return ${res}
  fi
}
