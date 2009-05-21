#!/bin/sh -x

# Convert DVD Title to PSP

SRC="-dvd-device /Users/sauber/Desktop/ISO/MONSTERS_INC dvd://5"
DST="/tmp/monsters-05-sample"
SAMPLE="-ss 25 -endpos 25"
#NTSC=",pullup,softskip"
#RESIZE=",crop=706:464:8:6,scale=720:400"
#SUBTITLE="-slang ja"
#AUDIOLANG="-alang en"

mencoder \
  $SAMPLE \
  -vf kerndeint$NTSC$RESIZE,expand=720:480,dsize=720:480,pp=al,denoise3d \
  $SUBTITLE \
  $AUDIOLANG -oac pcm -af volnorm \
  -ovc lavc -lavcopts vcodec=ffv1 -ofps 30000/1001 \
  $SRC -o $DST.mpg
#exit

ffmpeg \
  -i $DST.mpg \
  -acodec libfaac -ac 2 -ab 128k -ar 48000 \
  -vcodec libx264 -vpre hq -vpre main -refs 2 -b 1400k -bt 1400k -threads 0 \
  -psnr \
  -y $DST.mp4

rm $DST.mpg
