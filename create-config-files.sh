#!/bin/bash

AWS_IOT_DATA_ENDPOINT="d62tv5ad7ph83-ats.iot.us-west-1.amazonaws.com"
# AWS_IOT_DATA_ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS | jq -rM '.endpointAddress')
CERT_DIR="/path/to/aws-certs"

mkdir conf 2>/dev/null

for((i=1; i<=3; i++)) {

cat <<EOF > conf/config-${i}.json
{
  "topic": "trek10/initial",
  "broker": "${AWS_IOT_DATA_ENDPOINT}",
  "port": 8883,
  "keepalive": 60,
  "certificate": "${CERT_DIR}/trek10-cert.pem",
  "private_key": "${CERT_DIR}/trek10-priv-key.pem",
  "ca_bundle": "${CERT_DIR}/AmazonRootCA1.pem",
  "scale": "c"
}
EOF

}
