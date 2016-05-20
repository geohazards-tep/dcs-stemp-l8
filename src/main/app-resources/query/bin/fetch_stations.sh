#!/bin/bash

for region in naconf samer pac nz ant np europe africa seasia mideast
do
  region_url="http://weather.uwyo.edu/upperair/${region}.html"
  curl -s "${region_url}" \
    | grep "CIRCLE" | cut -d "'" -f 2 \
    | while read station
  do
    station_url="http://weather.uwyo.edu/cgi-bin/sounding?region=${region}&TYPE=TEXT%3AUNMERGED&YEAR=2016&MONTH=01&FROM=0100&TO=1512&STNM=${station}"
    read lat lon < <( curl -s "${station_url}" \
      | grep SLON | tr -s " " | cut -d " " -f 4,7 )
    echo ${station} ${lon} ${lat}
  done
done
