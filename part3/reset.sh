#!/bin/bash

BASE="/data/dev/iot/blog/scripts"
JOB_ID=$1

cd $BASE

rm -f ./conf/config-[0-9].*

./create-config-files.sh

aws iot delete-job --job-id ${JOB_ID} --force
