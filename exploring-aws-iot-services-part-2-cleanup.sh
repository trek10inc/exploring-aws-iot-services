#!/bin/bash

ROLE_1_NAME="trek10-iot-role-1"
ROLE_2_NAME="trek10-iot-role-2"
RULE_1_NAME="trek10_iot_rule_1"
RULE_2_NAME="trek10_iot_rule_2"
ERROR_ACTION_ROLE_NAME="trek10-iot-error-action-role"
LOG_GROUP="/aws/iot/trek10-iot-logs"
DYNAMODB_TABLE="trek10-iot-table"
S3_BUCKET="trek10-iot-bucket-rwendel"

ACCOUNT_ID="111222333444"
REGION="us-west-1"

TMP_FILE="/tmp/tmp-$$.json"

# delete our rules
aws iot delete-topic-rule --rule-name ${RULE_1_NAME}
aws iot delete-topic-rule --rule-name ${RULE_2_NAME}

# delete inline policies
aws iam list-role-policies --role-name $ROLE_1_NAME | jq -rM '.PolicyNames[]' | while read POLICY_NAME; do aws iam delete-role-policy --role-name $ROLE_1_NAME --policy-name $POLICY_NAME; done
aws iam list-role-policies --role-name $ROLE_2_NAME | jq -rM '.PolicyNames[]' | while read POLICY_NAME; do aws iam delete-role-policy --role-name $ROLE_2_NAME --policy-name $POLICY_NAME; done
aws iam list-role-policies --role-name $ERROR_ACTION_ROLE_NAME | jq -rM '.PolicyNames[]' | while read POLICY_NAME; do aws iam delete-role-policy --role-name $ERROR_ACTION_ROLE_NAME --policy-name $POLICY_NAME; done

# delete roles
aws iam delete-role --role-name $ROLE_1_NAME
aws iam delete-role --role-name $ROLE_2_NAME
aws iam delete-role --role-name $ERROR_ACTION_ROLE_NAME

# delete our log group
aws logs delete-log-group --log-group-name $LOG_GROUP

# delete our s3 bucket
aws s3api list-objects --bucket "${S3_BUCKET}" \
    --query='{Objects: Contents[].{Key:Key}}' > $TMP_FILE
aws s3api delete-objects --bucket "${S3_BUCKET}" \
    --delete file://${TMP_FILE}
aws s3api delete-bucket --bucket ${S3_BUCKET}

# delete our dynamodb table
aws dynamodb delete-table --table-name ${DYNAMODB_TABLE}

rm -f $TMP_FILE
