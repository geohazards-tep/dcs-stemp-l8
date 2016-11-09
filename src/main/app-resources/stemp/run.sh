#!/bin/bash

source /application/libexec/functions.sh

export LM_LICENSE_FILE=1700@idl.terradue.int
export MODTRAN_BIN=/opt/MODTRAN-5.4.0
export STEMP_BIN=/opt/STEMP/bin
export PROCESSING_HOME=${TMPDIR}/PROCESSING
export EMISSIVITY_AUX_PATH=${_CIOP_APPLICATION_PATH}/aux/INPUT_SRF

function main() {

  local ref=$1
  local identifier=$2
  local mission=$3
  local date=$4
  local station=$5
  local region=$6
  local volcano=$7
  local geom=$8

  local v_lon=$( echo "${geom}" | sed -n 's#POINT(\(.*\)\s.*)#\1#p')
  local v_lat=$( echo "${geom}" | sed -n 's#POINT(.*\s\(.*\))#\1#p')

  volcano=$( echo ${volcano} | tr ' ' _ )

  ciop-log "INFO" "**** STEMP node ****"
  ciop-log "INFO" "------------------------------------------------------------"
  ciop-log "INFO" "Mission: ${mission}"
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
  profile=$( getRas "${date}" "${station}" "${region}" "${PROCESSING_HOME}") || return ${ERR_GET_RAS}
  ciop-log "INFO" "Atmospheric profile downloaded"
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Getting Digital Elevation Model"
  dem=$( getDem "${geom}" "${PROCESSING_HOME}" ) || return ${ERR_GET_DEM}
  ciop-log "INFO" "Digital Elevation Model downloaded"
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Converting Digital Elevation Model to GeoTIFF"

  mv ${dem}.rsc ${PROCESSING_HOME}/dem.rsc
  mv ${dem} ${PROCESSING_HOME}/dem

  dem_geotiff=$( convertDemToGeoTIFF "${PROCESSING_HOME}/dem.rsc" "${PROCESSING_HOME}/dem" "${PROCESSING_HOME}" ) || return ${ERR_CONV_DEM}
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Croppig Digital Elevation Model"

  # Extent in degree
  local extent=0.3
  cropped_dem=$( cropDem "${dem_geotiff}" "${PROCESSING_HOME}" "${v_lon}" "${v_lat}" "${extent}" ) || return ${ERR_CROP_DEM}
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Getting input product"
  product=$( getData "${ref}" "${PROCESSING_HOME}" ) || return ${ERR_GET_DATA}
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
  [ ${res} -ne 0 ] && return ${$ERR_UNCOMP}
  ciop-log "INFO" "Product uncompressed"
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Getting the emissivity file and spectral response functions"
  ciop-log "INFO" "${EMISSIVITY_AUX_PATH}/${volcano}.tif"
  cp ${EMISSIVITY_AUX_PATH}/${volcano}.tif ${PROCESSING_HOME}
  cp ${EMISSIVITY_AUX_PATH}/*.txt ${PROCESSING_HOME}

  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Checking the UTM Zone"

  case ${mission,,} in
    landsat8)
        UTM_ZONE=$( sed -n 's#^.*UTM_ZONE\s=\s\(.*\)$#\1#p' ${PROCESSING_HOME}/${identifier}_MTL.txt )
    ;;
    aster)
        UTM_ZONE=$( gdalinfo ${PROCESSING_HOME}/${identifier}.hdf | sed -n 's#.*UTMZONENUMBER=\(.*\)#\1#p' )
    ;;
  esac

  ciop-log "INFO" "UTM Zone: ${UTM_ZONE}"

  # If the volcano is located in southern hemisphere
  if [ $( echo "${v_lat} < 0" | bc ) -eq 1 ]; then

    ciop-log "INFO" "Converting DEM to UTM Zone S"
    gdalwarp -t_srs "+proj=utm +zone=${UTM_ZONE} +south +datum=WGS84" ${cropped_dem} ${PROCESSING_HOME}/dem_UTM.TIF 1>&2

    if [ "${mission,,}" = "landsat8" ]; then
      ciop-log "INFO" "Setting the proper UTM Zone ${UTM_ZONE} for the B10 TIF"
      gdalwarp -t_srs "+proj=utm +zone=${UTM_ZONE} +south +ellps=WGS84 +datum=WGS84 +units=m +no_defs" ${PROCESSING_HOME}/${identifier}_B10.TIF ${PROCESSING_HOME}/${identifier}_B10_S.TIF 1>&2
      mv ${PROCESSING_HOME}/${identifier}_B10_S.TIF ${PROCESSING_HOME}/${identifier}_B10.TIF
      ciop-log "INFO" "------------------------------------------------------------"

      ciop-log "INFO" "Setting the proper UTM Zone ${UTM_ZONE} for the emissivity file"
      gdalwarp -t_srs "+proj=utm +zone=${UTM_ZONE} +south +datum=WGS84" ${PROCESSING_HOME}/${volcano}.tif ${PROCESSING_HOME}/${volcano}_S.tif 1>&2
      mv ${PROCESSING_HOME}/${volcano}_S.tif ${PROCESSING_HOME}/${volcano}.tif
      ciop-log "INFO" "------------------------------------------------------------"
    fi
    ciop-log "INFO" "------------------------------------------------------------"
  else
    ciop-log "INFO" "Converting DEM to UTM Zone N"
    gdalwarp -t_srs "+proj=utm +zone=${UTM_ZONE} +datum=WGS84" ${cropped_dem} ${PROCESSING_HOME}/dem_UTM.TIF 1>&2
    ciop-log "INFO" "------------------------------------------------------------"
  fi

  ciop-log "INFO" "Setting DEM resolution to 90m"
  gdalwarp -tr 90 -90 ${PROCESSING_HOME}/dem_UTM.TIF ${PROCESSING_HOME}/dem_UTM_90.TIF 1>&2
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Preparing file_input.cfg"
  case ${mission,,} in
    landsat8)
         echo "$( basename ${identifier})_B10.TIF" >> ${PROCESSING_HOME}/file_input.cfg
    ;;
    aster)
        echo "$( basename ${identifier}).hdf" >> ${PROCESSING_HOME}/file_input.cfg
    ;;
  esac

  basename ${profile} >> ${PROCESSING_HOME}/file_input.cfg
  echo "dem_UTM_90.TIF" >> ${PROCESSING_HOME}/file_input.cfg
  echo "${volcano}.tif" >> ${PROCESSING_HOME}/file_input.cfg

  ciop-log "INFO" "file_input.cfg content:"
  cat ${PROCESSING_HOME}/file_input.cfg 1>&2
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "PROCESSING_HOME content:"
  ls -l ${PROCESSING_HOME} 1>&2

  ciop-log "INFO" "STEMP environment ready"
  ciop-log "INFO" "------------------------------------------------------------"

  if [ "${DEBUG}" = "true" ]; then
    ciop-publish -m ${PROCESSING_HOME}/*_B10.TIF || return $?
    ciop-publish -m ${PROCESSING_HOME}/*txt || return $?
    ciop-publish -m ${PROCESSING_HOME}/dem* || return $?
    ciop-publish -m ${PROCESSING_HOME}/*${volcano}.tif || return $?
  fi

  ciop-log "INFO" "Starting STEMP core"
  /usr/local/bin/idl -rt=${STEMP_BIN}/STEMP.sav -IDL_DEVICE Z

  ciop-log "INFO" "STEMP core finished"
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Generating quicklooks"

  cd ${PROCESSING_HOME}
  string_inp=$(head -n 1 file_input.cfg)
  leng=${#string_inp}
  generateQuicklook ${PROCESSING_HOME}/${string_inp:0:leng-4}_TEMP.tif ${PROCESSING_HOME}
  #gdal_translate -scale -10 10 0 255 -ot Byte -of PNG ${string_inp:0:leng-4}_TEMP.tif ${string_inp:0:leng-4}_TEMP.png
  #listgeo -tfw ${string_inp:0:leng-4}_TEMP.tif
  #mv ${string_inp:0:leng-4}_TEMP.tfw ${string_inp:0:leng-4}_TEMP.pngw

  ciop-log "INFO" "Quicklooks generated:"
  ls -l ${PROCESSING_HOME}/*TEMP.png* 1>&2
  ciop-log "INFO" "------------------------------------------------------------"

METAFILE=${PROCESSING_HOME}/${identifier}_B10_TEMP.tif.properties
SATELLITE=$(sed -n 's#^.*SPACECRAFT_ID\s=\s\(.*\)$#\1#p' ${PROCESSING_HOME}/${identifier}_MTL.txt)
DATATIME=$(sed -n 's#^.*FILE_DATE\s=\s\(.*\)$#\1#p' ${PROCESSING_HOME}/${identifier}_MTL.txt)
SCENE=$(sed -n 's#^.*LANDSAT_SCENE_ID\s=\s\(.*\)$#\1#p' ${PROCESSING_HOME}/${identifier}_MTL.txt)
echo "#Predefined Metadata" >> ${METAFILE}
echo "title=STEMP - Surface Temperature Map - ${SCENE:1:21}" >> ${METAFILE}
echo "date=${DATATIME}" >> ${METAFILE}
echo "Volcano=${volcano}" >> ${METAFILE}
echo "#Input scene" >> ${METAFILE}
echo "Satellite=${SATELLITE:1:9}" >> ${METAFILE}
echo "Scene=${SCENE:1:21}" >> ${METAFILE}
echo "#STEMP Parameters" >> ${METAFILE}
echo "Emissivity=ASTER05" >> ${METAFILE}
echo "Atmospheric\ Profile=${profile}" >> ${METAFILE}
echo "DEM\ Spatial\ Resolution=90mt" >> ${METAFILE}
echo "Temperature\ Unit=degree" >> ${METAFILE}
echo "#EOF" >> ${METAFILE}

  ciop-log "INFO" "Staging-out results ..."
  ciop-publish -m ${PROCESSING_HOME}/*TEMP.tif || return $?
  ciop-publish -m ${PROCESSING_HOME}/*TEMP.png* || return $?
  ciop-publish -m ${METAFILE} || return $?
  [ ${res} -ne 0 ] && return ${ERR_PUBLISH}

  ciop-log "INFO" "Results staged out"
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Cleaning STEMP environment"
  rm -rf ${PROCESSING_HOME}/*
  ciop-log "INFO" "------------------------------------------------------------"
  ciop-log "INFO" "**** STEMP node finished ****"
}

while IFS=',' read ref identifier mission date station region volcano geom
do
    main "${ref}" "${identifier}" "${mission}" "${date}" "${station}" "${region}" "${volcano}" "${geom}" || exit $?
done

exit ${SUCCESS}
