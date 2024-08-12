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

cat <<EOF > /root/check-secrets.py
#!/usr/bin/env python3

import boto3
import json
import subprocess
import sys
import uuid

region_name = sys.argv[1]
arn = sys.argv[2]
enable_recording = sys.argv[3]
enable_etherpad = sys.argv[4]

client = boto3.client("secretsmanager", region_name=region_name)
response = client.get_secret_value(
  SecretId=arn
)
current_secret = json.loads(response["SecretString"])
needs_update = False

if 'password' in current_secret:
    needs_update = True
    del current_secret['password']
if 'username' in current_secret:
    needs_update = True
    del current_secret['username']
NEEDED_SECRETS_WITH_SIMILAR_REQUIREMENTS = [
    ".env:JICOFO_AUTH_PASSWORD",
    ".env:JVB_AUTH_PASSWORD",
    ".env:JIGASI_XMPP_PASSWORD",
    ".env:JIBRI_RECORDER_PASSWORD",
    ".env:JIBRI_XMPP_PASSWORD"
]
for secret in NEEDED_SECRETS_WITH_SIMILAR_REQUIREMENTS:
  if not secret in current_secret:
    needs_update = True
    cmd = "random_value=\$(seed=\$(date +%s%N); tr -dc '[:alnum:]' < /dev/urandom | head -c 32; echo \$seed | sha256sum | awk '{print substr(\$1, 1, 32)}'); echo \$random_value"
    output = subprocess.run(cmd, stdout=subprocess.PIPE, shell=True).stdout.decode('utf-8').strip()
    current_secret[secret] = output
if enable_recording == 'true' and current_secret.get('.env:ENABLE_RECORDING') != '1':
  needs_update = True
  current_secret['.env:ENABLE_RECORDING'] = '1'
if enable_recording == 'false' and current_secret.get('.env:ENABLE_RECORDING') == '1':
  needs_update = True
  del current_secret['.env:ENABLE_RECORDING']
if enable_etherpad == 'true' and current_secret.get('.env:ETHERPAD_URL_BASE') != 'http://etherpad.meet.jitsi:9001':
  needs_update = True
  current_secret['.env:ETHERPAD_URL_BASE'] = 'http://etherpad.meet.jitsi:9001'
if enable_etherpad == 'false' and current_secret.get('.env:ETHERPAD_URL_BASE') == 'http://etherpad.meet.jitsi:9001':
  needs_update = True
  del current_secret['.env:ETHERPAD_URL_BASE']
if needs_update:
  client.update_secret(
    SecretId=arn,
    SecretString=json.dumps(current_secret)
  )
else:
  print('Secrets already generated - no action needed.')
EOF
chown root:root /root/check-secrets.py
chmod 744 /root/check-secrets.py

/root/check-secrets.py ${AWS::Region} ${SecretArn} ${EnableRecording} ${EnableEtherpad}

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
