#!/bin/bash

# This script assumes that the error action role
# and log group have already been created and used
# by the first two rules featured in the accompanying
# blog post.

# general variables
ACCOUNT_ID="111222333444"
REGION="us-west-1"
TOPIC_1="trek10/initial"
TOPIC_2="trek10/final"
LOG_GROUP="/aws/iot/trek10-iot-logs"
ERROR_ACTION_ROLE_NAME="trek10-iot-error-action-role"
TOPIC="trek10-iot-topic"
TOPIC_DESCRIPTION="Topic to alert on IoT temperature extremes"
SUBSCRIPTION_EMAIL="rwendel@trek10.com"

# used by rule 3
ROLE_3_NAME="trek10-iot-role-3"
RULE_3_NAME="trek10_iot_rule_3"
RULE_3_DESCRIPTION="Trek10 IoT rule number 3"
RULE_3_QUERY="SELECT CONCAT('Device ', device, ' has a high temperature of ', temperature, ' degrees.') AS alert FROM '${TOPIC_2}' WHERE temperature > 120"

TMP_FILE="/tmp/tmp-$$.json"

aws sns create-topic --name ${TOPIC} \
    --attributes DisplayName="${TOPIC_DESCRIPTION}"

TOPIC_ARN="arn:aws:sns:${REGION}:${ACCOUNT_ID}:${TOPIC}"

aws sns subscribe --topic-arn ${TOPIC_ARN} \
    --protocol EMAIL \
    --notification-endpoint "${SUBSCRIPTION_EMAIL}" \
    --return-subscription-arn > ${TMP_FILE}

SUBSCRIPTION_ARN=$(cat ${TMP_FILE} | jq -rM '.SubscriptionArn')

cat <<EOF > /tmp/trek10-iot-role-3.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sns:Publish",
            "Resource": "${TOPIC_ARN}",
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

aws iam create-role --role-name ${ROLE_3_NAME} \
    --assume-role-policy-document file:///tmp/trek10-iot-trust-policy.json

aws iam put-role-policy --role-name ${ROLE_3_NAME} \
    --policy-name ${ROLE_3_NAME}-policy \
    --policy-document file:///tmp/trek10-iot-role-3.json

# need to sleep for a few seconds
sleep 10

# ROLE_3_ARN=$(aws iam get-role --role-name ${ROLE_3_NAME} | jq -rM '.Role.Arn')
# ERROR_ACTION_ROLE_ARN=$(aws iam get-role --role-name $ERROR_ACTION_ROLE_NAME | jq -rM '.Role.Arn')

ROLE_3_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_3_NAME}"
ERROR_ACTION_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ERROR_ACTION_ROLE_NAME}"

cat <<EOF > /tmp/trek10-rule-payload-3.json
{
    "sql":"${RULE_3_QUERY}",
    "description":"${RULE_3_DESCRIPTION}",
    "actions":[
        {
            "sns":{
                "targetArn":"${TOPIC_ARN}",
                "roleArn":"${ROLE_3_ARN}",
                "messageFormat":"RAW"
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

aws iot create-topic-rule --rule-name "${RULE_3_NAME}" --topic-rule-payload file:///tmp/trek10-rule-payload-3.json


