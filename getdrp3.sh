#!/bin/sh

#mplayer -dumpstream -dumpfile dr_p3_128.wmv -playlist http://www.dr.dk/netradio/Metafiler/asx/dr_p3_128.asx
#mplayer -endpos 10 -playlist http://www.dr.dk/netradio/Metafiler/asx/dr_p3_128.asx
while true ; do
  t=`date '+%F-%R'`
  mplayer -noconsolecontrols -dumpstream -dumpfile dr_p3_128-$t.wmv -playlist http://www.dr.dk/netradio/Metafiler/asx/dr_p3_128.asx &
  PID=$!
  sleep 1800
  kill $PID
  sleep 3
  kill -9 $PID
done
