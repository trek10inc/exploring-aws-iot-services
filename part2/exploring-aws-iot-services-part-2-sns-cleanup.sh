#!/bin/bash

# This script will not delete the error action role
# and log group that were created and used by the first
# two rules featured in the accompanying blog post. 

ROLE_3_NAME="trek10-iot-role-3"
RULE_3_NAME="trek10_iot_rule_3"
ERROR_ACTION_ROLE_NAME="trek10-iot-error-action-role"
LOG_GROUP="/aws/iot/trek10-iot-logs"
TOPIC="trek10-iot-topic"

ACCOUNT_ID="111222333444"
REGION="us-west-1"

TOPIC_ARN="arn:aws:sns:${REGION}:${ACCOUNT_ID}:${TOPIC}"

# delete our rules
aws iot delete-topic-rule --rule-name ${RULE_3_NAME}

# delete inline policies
aws iam list-role-policies --role-name $ROLE_3_NAME | jq -rM '.PolicyNames[]' | while read POLICY_NAME; do aws iam delete-role-policy --role-name $ROLE_3_NAME --policy-name $POLICY_NAME; done
# aws iam list-role-policies --role-name $ERROR_ACTION_ROLE_NAME | jq -rM '.PolicyNames[]' | while read POLICY_NAME; do aws iam delete-role-policy --role-name $ERROR_ACTION_ROLE_NAME --policy-name $POLICY_NAME; done

# delete roles
aws iam delete-role --role-name $ROLE_3_NAME
# aws iam delete-role --role-name $ERROR_ACTION_ROLE_NAME

# delete our log group
# aws logs delete-log-group --log-group-name $LOG_GROUP

# delete our sns topic
aws sns delete-topic --topic-arn ${TOPIC_ARN}
