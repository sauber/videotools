#!/bin/sh

# Converts a video file to psp format.
# Input must be 720:480 and correctly scaled, cropped etc.

# Optional:
#
#  -ab 128k \
#  -r 25 \
#  -ar 48000 \
#  -acodec libfaac \
#  -s 720x480 \
#  -vpre slower \
#  -vpre main \
#  -level 30 \
#  -refs 3 \
#  -flags2 \
#  -bpyramid-wpred \
#  -threads 0 \
#  -aspect 16:9 \
#  -maxrate 10M \
#  -bufsize 10M \

ffmpeg -i $1 \
  -ac 2 \
  -vcodec libx264 \
  -vpre normal \
  -vpre main \
  -level 30 \
  -b 1400k \
  -y $2
