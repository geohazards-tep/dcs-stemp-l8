#!/bin/bash

for region in naconf samer pac nz ant np europe africa seasia mideast
do
  region_url="http://weather.uwyo.edu/upperair/${region}.html"
  curl -s "${region_url}" \
    | grep "CIRCLE" | cut -d "'" -f 2 \
    | while read station
  do
    # change accordingly the year and month values if a station doesn't provide results
    year="2016"
    month="01"
    station_url="http://weather.uwyo.edu/cgi-bin/sounding?region=${region}&TYPE=TEXT%3AUNMERGED&YEAR=${year}&MONTH=${month}&FROM=all&TO=3112&STNM=${station}"
    read lat lon < <( curl -s "${station_url}" \
      | grep SLON | tr -s " " | cut -d " " -f 4,7 )
    echo ${region} ${station} ${lon} ${lat}
  done
done
