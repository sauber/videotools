#!/bin/sh

#mplayer -dumpstream -dumpfile dr_p3_128.wmv -playlist http://www.dr.dk/netradio/Metafiler/asx/dr_p3_128.asx
#mplayer -endpos 10 -playlist http://www.dr.dk/netradio/Metafiler/asx/dr_p3_128.asx
#url=http://somafm.com/play/beatblender
url=http://voxsc1.somafm.com:8900
streamfile=beatblender.mp3
while true ; do
  t=`date '+%F-%R'`
  mplayer -noconsolecontrols -dumpstream -dumpfile $t-$streamfile $url &
  PID=$!
  sleep 1800
  kill $PID
  sleep 3
  kill -9 $PID
done
