#!/bin/bash

# general variables
ACCOUNT_ID="111222333444"
REGION="us-west-1"
TOPIC_1="trek10/initial"
TOPIC_2="trek10/final"
LOG_GROUP="/aws/iot/trek10-iot-logs"
ERROR_ACTION_ROLE_NAME="trek10-iot-error-action-role"
DYNAMODB_TABLE="trek10-iot-table"
S3_BUCKET="trek10-iot-bucket-rwendel"

# used by rule 1
ROLE_1_NAME="trek10-iot-role-1"
RULE_1_NAME="trek10_iot_rule_1"
RULE_1_DESCRIPTION="Trek10 IoT rule number 1"
RULE_1_QUERY="SELECT timestamp, device, timestamp() as received, humidity, barometer, wind.velocity as wind_speed, wind.bearing as wind_direction, CASE scale WHEN 'c' THEN (temperature * 1.8) + 32 ELSE temperature END as temperature FROM '${TOPIC_1}'"

# used by rule 2
ROLE_2_NAME="trek10-iot-role-2"
RULE_2_NAME="trek10_iot_rule_2"
RULE_2_DESCRIPTION="Trek10 IoT rule number 2"
RULE_2_QUERY="SELECT * FROM '${TOPIC_2}'"
S3_KEY="\${parse_time('yyyy', timestamp(), 'UTC')}/\${parse_time('MM', timestamp(), 'UTC')}/\${parse_time('dd', timestamp(), 'UTC')}/\${parse_time('HH', timestamp(), 'UTC')}/\${device}/\${timestamp()}"

cat <<EOF > /tmp/trek10-iot-role-1.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "iot:Publish",
            "Resource": "arn:aws:iot:${REGION}:${ACCOUNT_ID}:topic/${TOPIC_2}",
            "Effect": "Allow"
        }
    ]
}
EOF


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

aws iam create-role --role-name ${ROLE_1_NAME} \
    --assume-role-policy-document file:///tmp/trek10-iot-trust-policy.json

aws iam put-role-policy --role-name ${ROLE_1_NAME} \
    --policy-name ${ROLE_1_NAME}-policy \
    --policy-document file:///tmp/trek10-iot-role-1.json

aws logs create-log-group --log-group-name ${LOG_GROUP}

aws logs put-retention-policy --log-group-name ${LOG_GROUP} \
    --retention-in-days 1

cat <<EOF > /tmp/trek10-iot-error-action-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "logs:CreateLogStream",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*",
            "Effect": "Allow"
        }
    ]
}
EOF

aws iam create-role --role-name ${ERROR_ACTION_ROLE_NAME} \
    --assume-role-policy-document file:///tmp/trek10-iot-trust-policy.json

aws iam put-role-policy --role-name ${ERROR_ACTION_ROLE_NAME} \
    --policy-name ${ERROR_ACTION_ROLE_NAME}-policy \
    --policy-document file:///tmp/trek10-iot-error-action-policy.json

# need to sleep for a few seconds
sleep 10

# ROLE_1_ARN=$(aws iam get-role --role-name ${ROLE_1_NAME} | jq -rM '.Role.Arn')
# ERROR_ACTION_ROLE_ARN=$(aws iam get-role --role-name $ERROR_ACTION_ROLE_NAME | jq -rM '.Role.Arn')

ROLE_1_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_1_NAME}"
ERROR_ACTION_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ERROR_ACTION_ROLE_NAME}"

cat <<EOF > /tmp/trek10-rule-payload-1.json
{
    "sql":"${RULE_1_QUERY}",
    "description":"${RULE_1_DESCRIPTION}",
    "actions":[
        {
            "republish":{
                "roleArn":"${ROLE_1_ARN}",
                "topic":"${TOPIC_2}",
                "qos":1
            }
        }
    ],
    "awsIotSqlVersion": "2016-03-23",
    "errorAction":{
        "cloudwatchLogs":{
            "roleArn":"${ERROR_ACTION_ROLE_ARN}",
            "logGroupName":"${LOG_GROUP}"
        }
    }
}
EOF

aws iot create-topic-rule --rule-name "${RULE_1_NAME}" --topic-rule-payload file:///tmp/trek10-rule-payload-1.json

aws s3api create-bucket --bucket ${S3_BUCKET} \
    --create-bucket-configuration LocationConstraint=${REGION} \
    --region ${REGION}
aws s3api put-public-access-block --bucket ${S3_BUCKET} \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

aws dynamodb create-table \
    --table-name ${DYNAMODB_TABLE} \
    --attribute-definitions \
        AttributeName=device,AttributeType=N \
        AttributeName=timestamp,AttributeType=N \
    --key-schema \
        AttributeName=device,KeyType=HASH \
        AttributeName=timestamp,KeyType=RANGE \
    --billing-mode PROVISIONED \
    --provisioned-throughput ReadCapacityUnits=3,WriteCapacityUnits=3

cat <<EOF > /tmp/trek10-iot-role-2.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "dynamodb:PutItem",
            "Resource": "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${DYNAMODB_TABLE}",
            "Effect": "Allow"
        },
        {
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${S3_BUCKET}/*",
            "Effect": "Allow"
        }
    ]
}
EOF

aws iam create-role --role-name ${ROLE_2_NAME} \
    --assume-role-policy-document file:///tmp/trek10-iot-trust-policy.json

aws iam put-role-policy --role-name ${ROLE_2_NAME} \
    --policy-name ${ROLE_2_NAME}-policy \
    --policy-document file:///tmp/trek10-iot-role-2.json

# need to sleep for a few seconds
sleep 10

# ROLE_2_ARN=$(aws iam get-role --role-name ${ROLE_2_NAME} | jq -rM '.Role.Arn')
ROLE_2_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_2_NAME}"

cat <<EOF > /tmp/trek10-rule-payload-2.json
{
    "sql":"${RULE_2_QUERY}",
    "description":"${RULE_2_DESCRIPTION}",
    "actions":[
        {
            "dynamoDBv2":{
                "roleArn":"${ROLE_2_ARN}",
                "putItem":{
                    "tableName":"${DYNAMODB_TABLE}"
                }
            }
        },
        {
            "s3":{
                "roleArn":"${ROLE_2_ARN}",
                "bucketName":"${S3_BUCKET}",
                "key":"${S3_KEY}"
            }
        }
    ],
    "awsIotSqlVersion": "2016-03-23",
    "errorAction":{
        "cloudwatchLogs":{
            "roleArn":"${ERROR_ACTION_ROLE_ARN}",
            "logGroupName":"${LOG_GROUP}"
        }
    }
}
EOF

aws iot create-topic-rule --rule-name "${RULE_2_NAME}" --topic-rule-payload file:///tmp/trek10-rule-payload-2.json
