#!/bin/bash

# general variables
ACCOUNT_ID="111222333444"
REGION="us-west-1"
CERT_ARN="arn:aws:iot:${REGION}:${ACCOUNT_ID}:cert/d52b026bd11754c44fbe42d165ba168465a1b055aa9d113e3261f579c69aabaf"
CERT_DIR="/path/to/aws-certs"
IOT_POLICY_NAME="trek10-iot-policy-2"
IOT_DATA_ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS | jq -rM '.endpointAddress')
JOB_ID="job-1"
S3_BUCKET="trek10-iot-bucket-rwendel"
S3_PRESIGN_ROLE="trek10-iot-job-role"
THING_PREFIX="trek10-thing"
THING_GROUP="trek10-thing-group-1"
THING_START=1
THING_STOP=3
TOPIC_1="trek10/initial"
TOPIC_2="trek10/final"
TMP_FILE="/tmp/tmp.$$.txt"

# delete the job (if it exists)
if aws iot describe-job --job-id ${JOB_ID} 2>/dev/null; then
    aws iot delete-job --job-id ${JOB_ID} --force
fi

# delete the things
for((i=${THING_START}; i<=${THING_STOP}; i++)) {
    # dis-associate our certificate a thing 
    aws iot detach-thing-principal --thing-name ${THING_PREFIX}-${i} \
    --principal ${CERT_ARN}

    # delete a thing
    aws iot delete-thing --thing-name ${THING_PREFIX}-${i}
}

# delete the thing group
aws iot delete-thing-group --thing-group-name ${THING_GROUP}

# delete the inline S3 presign role policies
aws iam list-role-policies --role-name $S3_PRESIGN_ROLE | jq -rM '.PolicyNames[]' | while read POLICY_NAME; do aws iam delete-role-policy --role-name $S3_PRESIGN_ROLE --policy-name $POLICY_NAME; done

# delete S3 presign role
aws iam delete-role --role-name $S3_PRESIGN_ROLE

#  detach our cert from our policy
aws iot detach-principal-policy --principal ${CERT_ARN} --policy-name ${IOT_POLICY_NAME}

# delete the IoT policy
aws iot delete-policy --policy-name ${IOT_POLICY_NAME}

# delete our s3 bucket
PROMPT="Do you wish to delete the S3 bucket (y/n)? "

read -p "${PROMPT}" yn
case $yn in
  [Yy]* )
    aws s3api list-objects --bucket "${S3_BUCKET}" \
        --query='{Objects: Contents[].{Key:Key}}' > $TMP_FILE
    aws s3api delete-objects --bucket "${S3_BUCKET}" \
        --delete file://${TMP_FILE}
    aws s3api delete-bucket --bucket ${S3_BUCKET}
    ;;
  [Nn]* )
    ;;
  * )
    echo ${PROMPT}
    ;;
esac

rm -f ${TMP_FILE}
