#!/bin/bash

# aws cloudwatch
sed -i 's/ASG_APP_LOG_GROUP_PLACEHOLDER/${AsgAppLogGroup}/g' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
sed -i 's/ASG_SYSTEM_LOG_GROUP_PLACEHOLDER/${AsgSystemLogGroup}/g' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

function error_exit
{
    cfn-signal --exit-code 1 --stack ${AWS::StackName} --resource Asg --region ${AWS::Region}
    exit 1
}

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)

function insert_logging_config() {
  local SERVICE=$1
  local LINE_NUMBER=$2
  local FILE=$3

  TEXT=$(cat <<EOF
        logging:
            driver: awslogs
            options:
                awslogs-group: ${AsgAppLogGroup}
                awslogs-stream: $INSTANCE_ID-${!SERVICE}
EOF
  )
  TEMP_FILE=$(mktemp)
  awk -v n="$LINE_NUMBER" -v text="$TEXT" 'NR == n {print text} {print}' "$FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$FILE"
}
insert_logging_config "jvb" 419 "/root/jitsi-docker-jitsi-meet/docker-compose.yml"
insert_logging_config "jicofo" 332 "/root/jitsi-docker-jitsi-meet/docker-compose.yml"
insert_logging_config "prosody" 187 "/root/jitsi-docker-jitsi-meet/docker-compose.yml"
insert_logging_config "web" 6 "/root/jitsi-docker-jitsi-meet/docker-compose.yml"
insert_logging_config "jibri" 5 "/root/jitsi-docker-jitsi-meet/jibri.yml"
insert_logging_config "jigasi" 6 "/root/jitsi-docker-jitsi-meet/jigasi.yml"
insert_logging_config "etherpad" 6 "/root/jitsi-docker-jitsi-meet/etherpad.yml"
insert_logging_config "transcriber" 5 "/root/jitsi-docker-jitsi-meet/transcriber.yml"

echo 's3fs#${AssetsBucket} /s3 fuse _netdev,allow_other,nonempty,iam_role=${IamRole} 0 0' >> /etc/fstab
rm -rf /s3 && mkdir /s3
mount -a
mkdir -p /s3/jitsi-meet-cfg/{web,transcripts,prosody/config,prosody/prosody-plugins-custom,jicofo,jvb,jigasi,jibri}

# find NLB static IPs
dns_name="${Hostname}"
ips=$(dig +short $dns_name)
# Parse the IPs
ip_array=($ips)
ip1=${!ip_array[0]}
ip2=${!ip_array[1]}

/root/check-secrets.py ${AWS::Region} ${SecretArn}

mkdir -p /opt/oe/patterns
SECRET_NAME=$(aws secretsmanager describe-secret --secret-id ${SecretArn} | jq -r .Name)
aws ssm get-parameter \
    --name "/aws/reference/secretsmanager/$SECRET_NAME" \
    --with-decryption \
    --query Parameter.Value \
| jq -r . > /opt/oe/patterns/instance.json

JICOFO_AUTH_PASSWORD=$(cat /opt/oe/patterns/instance.json | jq -r .JICOFO_AUTH_PASSWORD)
JVB_AUTH_PASSWORD=$(cat /opt/oe/patterns/instance.json | jq -r .JVB_AUTH_PASSWORD)
JIGASI_XMPP_PASSWORD=$(cat /opt/oe/patterns/instance.json | jq -r .JIGASI_XMPP_PASSWORD)
JIBRI_RECORDER_PASSWORD=$(cat /opt/oe/patterns/instance.json | jq -r .JIBRI_RECORDER_PASSWORD)
JIBRI_XMPP_PASSWORD=$(cat /opt/oe/patterns/instance.json | jq -r .JIBRI_XMPP_PASSWORD)
JIGASI_TRANSCRIBER_PASSWORD=$(cat /opt/oe/patterns/instance.json | jq -r .JIGASI_TRANSCRIBER_PASSWORD)

JITSI_IMAGE_VERSION=$(cat /root/jitsi-image-version)
# custom .env
CUSTOM_DOT_ENV_CONFIG="# no custom config defined"
if [[ "${CustomDotEnvParameterArn}" != "" ]]; then
    CUSTOM_DOT_ENV_CONFIG_TITLE="# custom config fetched from ${CustomDotEnvParameterArn}"
    CUSTOM_DOT_ENV_CONFIG_VALUE=$(aws ssm get-parameter --name "${CustomDotEnvParameterArn}" --with-decryption --output text --query Parameter.Value)
    CUSTOM_DOT_ENV_CONFIG=$(printf "%s\n\n%s" "$CUSTOM_DOT_ENV_CONFIG_TITLE" "$CUSTOM_DOT_ENV_CONFIG_VALUE")
fi
cat <<EOF > /root/jitsi-docker-jitsi-meet/.env
CONFIG=/s3/jitsi-meet-cfg
HTTP_PORT=80
HTTPS_PORT=443
TZ=UTC
PUBLIC_URL=https://${Hostname}
JVB_ADVERTISE_IPS=$ip1,$ip2
ENABLE_LETSENCRYPT=0
JITSI_IMAGE_VERSION=$JITSI_IMAGE_VERSION

JICOFO_AUTH_PASSWORD=$JICOFO_AUTH_PASSWORD
JVB_AUTH_PASSWORD=$JVB_AUTH_PASSWORD
JIGASI_XMPP_PASSWORD=$JIGASI_XMPP_PASSWORD
JIGASI_TRANSCRIBER_PASSWORD=$JIGASI_TRANSCRIBER_PASSWORD
JIBRI_RECORDER_PASSWORD=$JIBRI_RECORDER_PASSWORD
JIBRI_XMPP_PASSWORD=$JIBRI_XMPP_PASSWORD

$CUSTOM_DOT_ENV_CONFIG
EOF

cat <<EOF > /root/start.sh
#!/usr/bin/env bash
cd /root/jitsi-docker-jitsi-meet
DOCKER_FILES="-f docker-compose.yml"
if grep -q '^ENABLE_RECORDING=1' .env; then
  DOCKER_FILES="\$DOCKER_FILES -f jibri.yml"
fi
if grep -q '^ENABLE_TRANSCRIPTIONS=1' .env; then
  DOCKER_FILES="\$DOCKER_FILES -f transcriber.yml"
fi
if grep -q '^ETHERPAD_URL_BASE=' .env; then
  DOCKER_FILES="\$DOCKER_FILES -f etherpad.yml"
fi
if grep -q '^JIGASI_SIP_URI=' .env; then
  DOCKER_FILES="\$DOCKER_FILES -f jigasi.yml"
fi
docker compose \$DOCKER_FILES up -d
EOF
cat <<EOF > /root/stop.sh
#!/usr/bin/env bash
cd /root/jitsi-docker-jitsi-meet
docker compose down
EOF
cat <<EOF > /root/restart.sh
#!/usr/bin/env bash
/root/stop.sh && /root/start.sh
EOF
chmod 755 /root/start.sh
chmod 755 /root/stop.sh
chmod 755 /root/restart.sh

cat <<EOF > /etc/systemd/system/jitsi.service
[Unit]
Description=jitsi
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/root/start.sh
ExecStop=/root/stop.sh
WorkingDirectory=/root/jitsi-docker-jitsi-meet

[Install]
WantedBy=multi-user.target
EOF
# custom-config.js
CUSTOM_CONFIG_JS_CONFIG="// no custom config defined"
if [[ "${CustomConfigJsParameterArn}" != "" ]]; then
    CUSTOM_CONFIG_JS_CONFIG_TITLE="// custom config fetched from ${CustomConfigJsParameterArn}"
    CUSTOM_CONFIG_JS_CONFIG_VALUE=$(aws ssm get-parameter --name "${CustomConfigJsParameterArn}" --with-decryption --output text --query Parameter.Value)
    CUSTOM_CONFIG_JS_CONFIG=$(printf "%s\n\n%s" "$CUSTOM_CONFIG_JS_CONFIG_TITLE" "$CUSTOM_CONFIG_JS_CONFIG_VALUE")
fi
# custom-interface_config.js
CUSTOM_INTERFACE_CONFIG_JS_CONFIG="// no custom config defined"
if [[ "${CustomInterfaceConfigJsParameterArn}" != "" ]]; then
    CUSTOM_INTERFACE_CONFIG_JS_CONFIG_TITLE="// custom config fetched from ${CustomInterfaceConfigJsParameterArn}"
    CUSTOM_INTERFACE_CONFIG_JS_CONFIG_VALUE=$(aws ssm get-parameter --name "${CustomInterfaceConfigJsParameterArn}" --with-decryption --output text --query Parameter.Value)
    CUSTOM_INTERFACE_CONFIG_JS_CONFIG=$(printf "%s\n\n%s" "$CUSTOM_INTERFACE_CONFIG_JS_CONFIG_TITLE" "$CUSTOM_INTERFACE_CONFIG_JS_CONFIG_VALUE")
fi
echo "$CUSTOM_CONFIG_JS_CONFIG" > /s3/jitsi-meet-cfg/web/custom-config.js
echo "$CUSTOM_INTERFACE_CONFIG_JS_CONFIG" > /s3/jitsi-meet-cfg/web/custom-interface_config.js

systemctl enable jitsi.service
systemctl start jitsi.service
success=$?

#
# cloudformation signal
#

cfn-signal --exit-code $success --stack ${AWS::StackName} --resource Asg --region ${AWS::Region}
