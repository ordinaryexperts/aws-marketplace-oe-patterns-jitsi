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

INSTANCE_ID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`

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
insert_logging_config "jvb" 399 "/root/jitsi-docker-jitsi-meet/docker-compose.yml"
insert_logging_config "jicofo" 316 "/root/jitsi-docker-jitsi-meet/docker-compose.yml"
insert_logging_config "prosody" 183 "/root/jitsi-docker-jitsi-meet/docker-compose.yml"
insert_logging_config "web" 6 "/root/jitsi-docker-jitsi-meet/docker-compose.yml"
insert_logging_config "jibri" 5 "/root/jitsi-docker-jitsi-meet/jibri.yml"
insert_logging_config "jigasi" 6 "/root/jitsi-docker-jitsi-meet/jigasi.yml"
insert_logging_config "etherpad" 6 "/root/jitsi-docker-jitsi-meet/etherpad.yml"

echo 's3fs#${AssetsBucket} /s3 fuse _netdev,allow_other,nonempty,iam_role=auto 0 0' >> /etc/fstab
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

cat <<EOF > /root/jitsi-docker-jitsi-meet/.env
CONFIG=/s3/jitsi-meet-cfg
HTTP_PORT=80
HTTPS_PORT=443
TZ=UTC
PUBLIC_URL=https://${Hostname}
JVB_ADVERTISE_IPS=$ip1,$ip2
ENABLE_LETSENCRYPT=0
EOF

cat <<EOF > /root/start.sh
#!/usr/bin/env bash
cd /root/jitsi-docker-jitsi-meet
DOCKER_FILES="-f docker-compose.yml"
if grep -q '^ENABLE_RECORDING=1' .env; then
  DOCKER_FILES="\$DOCKER_FILES -f jibri.yml"
fi
if grep -q '^JIGASI_SIP_URI=' .env; then
  DOCKER_FILES="\$DOCKER_FILES -f jigasi.yml"
fi
if grep -q '^ETHERPAD_URL_BASE=' .env; then
  DOCKER_FILES="\$DOCKER_FILES -f etherpad.yml"
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

rm -f /s3/jitsi-meet-cfg/web/custom-config.js
rm -f /s3/jitsi-meet-cfg/web/custom-interface_config.js
/root/append-config.py

systemctl enable jitsi.service
systemctl start jitsi.service
success=$?

#
# cloudformation signal
#

cfn-signal --exit-code $success --stack ${AWS::StackName} --resource Asg --region ${AWS::Region}
