#!/bin/bash

# general variables
ACCOUNT_ID="111222333444"
REGION="us-west-1"
CERT_ARN="arn:aws:iot:${REGION}:${ACCOUNT_ID}:cert/f54e026bd11784c44fbe42d165ba168465a1b055aa9d113e3261f579c69aabaf"
CERT_DIR="/data/dev/iot/aws-certs"
CONFIG_FILE="config.json"
CONFIG_FILE_S3_FOLDER="config"
IOT_POLICY_NAME="trek10-iot-policy-2"
IOT_DATA_ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS | jq -rM '.endpointAddress')
JOB_DOCUMENT_FILE="trek10-iot-job-document-1.json"
JOB_DOCUMENT_S3_FOLDER="jobs"
S3_BUCKET="trek10-iot-bucket-rwendel"
S3_PRESIGN_ROLE="trek10-iot-job-role"
THING_PREFIX="trek10-thing"
THING_GROUP="trek10-thing-group-1"
THING_START=1
THING_STOP=3
TOPIC_1="trek10/initial"
TOPIC_2="trek10/final"
TMP_FILE="/tmp/tmp.$$.txt"

# create our bucket if it doesn't already exist
if ! aws s3api head-bucket --bucket ${S3_BUCKET} 2>/dev/null; then
    # create the bucket
    aws s3api create-bucket --bucket ${S3_BUCKET} \
        --create-bucket-configuration LocationConstraint=${REGION} \
        --region ${REGION}

    # block public access to bucket
    aws s3api put-public-access-block --bucket trek10-iot-bucket-rwendel \
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
fi

# create the job document
cat <<EOF > /tmp/${JOB_DOCUMENT_FILE}
{
    "action": "config",
    "url": "\${aws:iot:s3-presigned-url:https://s3.amazonaws.com/trek10-iot-bucket-rwendel/config/config.json}"
}
EOF

# copy the job document to our bucket
aws s3 cp /tmp/${JOB_DOCUMENT_FILE} s3://${S3_BUCKET}/${JOB_DOCUMENT_S3_FOLDER}/${JOB_DOCUMENT_FILE}

# build our job role
cat <<EOF > /tmp/trek10-iot-trust-policy.json
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "iot.amazonaws.com"
            },
            "Action": [
                "sts:AssumeRole"
            ]
        }
    ]
}
EOF

cat <<EOF > /tmp/trek10-iot-job-role.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${S3_BUCKET}/*",
            "Effect": "Allow"
        }
    ]
}
EOF

aws iam create-role --role-name ${S3_PRESIGN_ROLE} \
    --assume-role-policy-document file:///tmp/trek10-iot-trust-policy.json

aws iam put-role-policy --role-name ${S3_PRESIGN_ROLE} \
    --policy-name ${S3_PRESIGN_ROLE}-policy \
    --policy-document file:///tmp/trek10-iot-job-role.json

# need to sleep for a few seconds
# sleep 10

# S3_PRESIGN_ROLE_ARN=$(aws iam get-role --role-name ${S3_PRESIGN_ROLE} | jq -rM '.Role.Arn')
S3_PRESIGN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${S3_PRESIGN_ROLE}"

# echo $S3_PRESIGN_ROLE_ARN

# create our IoT policy
cat <<EOF > /tmp/trek10-iot-policy-2.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:${REGION}:${ACCOUNT_ID}:client/\${iot:ClientId}"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": [
        "arn:aws:iot:${REGION}:${ACCOUNT_ID}:topic/trek10/*",
        "arn:aws:iot:${REGION}:${ACCOUNT_ID}:topic/\$aws/things/\${iot:Connection.Thing.ThingName}/jobs/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "iot:Receive",
      "Resource": [
        "arn:aws:iot:${REGION}:${ACCOUNT_ID}:topic/\$aws/things/\${iot:Connection.Thing.ThingName}/jobs/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "iot:Subscribe",
      "Resource": [
        "arn:aws:iot:${REGION}:${ACCOUNT_ID}:topicfilter/\$aws/things/\${iot:Connection.Thing.ThingName}/jobs/*"
      ]
    }
  ]
}
EOF

aws iot create-policy --policy-name ${IOT_POLICY_NAME} --policy-document file:///tmp/trek10-iot-policy-2.json

# attach our cert to our policy
aws iot attach-principal-policy --principal ${CERT_ARN} --policy-name ${IOT_POLICY_NAME}

# create a thing group
aws iot create-thing-group --thing-group-name ${THING_GROUP} \
    --thing-group-properties thingGroupDescription="Group to store IoT demo things"

# create and configure our thing fleet
for((i=${THING_START}; i<=${THING_STOP}; i++)) {
    # create a thing
    aws iot create-thing --thing-name ${THING_PREFIX}-${i}

    # associate our certificate with the created thing 
    aws iot attach-thing-principal --thing-name ${THING_PREFIX}-${i} \
    --principal ${CERT_ARN}

    # add our thing to the newly created thing group
    aws iot add-thing-to-thing-group --thing-group-name ${THING_GROUP} \
    --thing-name ${THING_PREFIX}-${i}

}

# create the updated config file being pushed to devices
cat <<EOF > /tmp/${CONFIG_FILE}
{
    "topic": "${TOPIC_1}",
    "broker": "${IOT_DATA_ENDPOINT}",
    "port": 8883,
    "keepalive": 60,
    "certificate": "${CERT_DIR}/trek10-cert.pem",
    "private_key": "${CERT_DIR}/trek10-priv-key.pem",
    "ca_bundle": "${CERT_DIR}/AmazonRootCA1.pem",
    "scale": "f"
}
EOF

# copy the new config to S3 so our devices can download
aws s3 cp /tmp/${CONFIG_FILE} s3://${S3_BUCKET}/${CONFIG_FILE_FOLDER}/${CONFIG_FILE}