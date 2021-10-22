#!/bin/bash
#
# Jibri will call us with $1 as the directory of the recording.
DIR=$1
echo "Recording processor for recording of directory $DIR"

## encoding quality (lower == better)
# 23 is about 1.5x aka 45 FPS average on my hardware (6 core 12 thread Xeon 2.6GHz)
QENC=23
#scaling (captured video is 720p)
#this one scales to 360p (divides by 2 both dimensions, keeping aspect 16:9)
#VSCALE="-vf scale=iw/2:-1"
#this one scales to 960p
VSCALE="-vf scale=960:-1"
cftb_bucketname_key=s3://jibri-rec001/newRecordings/
cftb_sourcefile=*.mp4
echo "Processing from $DIR/$cftb_sourcefile to $cftb_bucketname_key"

#Move into the Folder where the video is located
cd $DIR
#Find the mp4 file created for the recording
#It creates a metadata.json file I am not uploading it yet
mp4_file_path=$(find -name "$cftb_sourcefile")
echo "cftb_bucketname_key: $cftb_bucketname_key"
echo "mp4_file_path: $mp4_file_path"
RESPONSE=$(aws s3 cp \
      $mp4_file_path \
      $cftb_bucketname_key)

if [[ ${?} -ne 0 ]]; then
      errecho "ERROR: AWS reports put-object operation failed.\n$RESPONSE"
      return 1
fi
