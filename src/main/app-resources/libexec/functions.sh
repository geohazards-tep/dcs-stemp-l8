#!/bin/bash
 
# source the ciop functions (e.g. ciop-log)
source ${ciop_job_include}

export PATH=/opt/anaconda/bin:/application/bin:$PATH 

SUCCESS=0
ERR_INVALID_MISSION=10
ERR_VOLCANO_NOT_FOUND=11
ERR_STATION_NOT_FOUND=12
ERR_RAS=13
ERR_AOI=14
ERR_PUBLISH=15

# add a trap to exit gracefully
function cleanExit ()
{
  local retval=$?
  local msg=""
  case "$retval" in
    $SUCCESS)               msg="Processing successfully concluded";;
    $ERR_INVALID_MISSION)   msg="Invalid mission";;
    $ERR_VOLCANO_NOT_FOUND) msg="Volcano not found in the db";;
    $ERR_STATION_NOT_FOUND) msg="Sounding station not found";;
    $ERR_RAS)               msg="Athmosferic profile is not available";;
    $ERR_AOI)               msg="The selected input file does not contain a correct area to be processed";;
    $ERR_PUBLISH)           msg="Failed results publish";;
    *)                      msg="Unknown error";;
  esac
  [ "$retval" != "0" ] && ciop-log "ERROR" "Error $retval - $msg, processing aborted" || ciop-log "INFO" "$msg"
  exit $retval
}

trap cleanExit EXIT
