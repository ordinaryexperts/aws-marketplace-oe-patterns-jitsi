SCRIPT_VERSION=1.6.0
SCRIPT_PREINSTALL=ubuntu_2204_2404_preinstall.sh
SCRIPT_POSTINSTALL=ubuntu_2204_2404_postinstall.sh

# preinstall steps
apt-get update && apt-get -y install curl
curl -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_PREINSTALL"
chmod +x $SCRIPT_PREINSTALL
./$SCRIPT_PREINSTALL
rm $SCRIPT_PREINSTALL

#
# Jitsi configuration
#  * https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-quickstart
#

# cloudwatch config
cat <<EOF > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root",
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "metrics": {
    "metrics_collected": {
      "collectd": {
        "metrics_aggregation_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      }
    },
    "append_dimensions": {
      "ImageId": "\${aws:ImageId}",
      "InstanceId": "\${aws:InstanceId}",
      "InstanceType": "\${aws:InstanceType}",
      "AutoScalingGroupName": "\${aws:AutoScalingGroupName}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/dpkg.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/dpkg.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apt/history.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/apt/history.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/cloud-init.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/cloud-init-output.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/auth.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/syslog",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/amazon/ssm/amazon-ssm-agent.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/amazon/ssm/amazon-ssm-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/amazon/ssm/errors.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/amazon/ssm/errors.log",
            "timezone": "UTC"
          }
        ]
      }
    },
    "log_stream_name": "{instance_id}"
  }
}
EOF

#
# Jitsi configuration
#

# https://github.com/jitsi/docker-jitsi-meet/releases/tag/stable-9823 # 11/12/2024
JITSI_VERSION=stable-9823

cd /root
echo $JITSI_VERSION >> /root/jitsi-image-version

# s3fs
apt-get update && apt-get -y install s3fs

# install Docker
curl https://get.docker.com -o install-docker.sh
sh install-docker.sh

wget $(curl -s https://api.github.com/repos/jitsi/docker-jitsi-meet/releases/tags/$JITSI_VERSION | grep 'zip' | cut -d\" -f4)
unzip $JITSI_VERSION
mv jitsi-docker-jitsi-meet-* jitsi-docker-jitsi-meet
cd jitsi-docker-jitsi-meet
docker compose -f docker-compose.yml -f jibri.yml -f etherpad.yml -f jigasi.yml pull
cd /root

pip install boto3
cat <<EOF > /root/check-secrets.py
#!/usr/bin/env python3

import boto3
import json
import subprocess
import sys
import uuid

region_name = sys.argv[1]
arn = sys.argv[2]

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
    "JICOFO_AUTH_PASSWORD",
    "JVB_AUTH_PASSWORD",
    "JIGASI_XMPP_PASSWORD",
    "JIGASI_TRANSCRIBER_PASSWORD",
    "JIBRI_RECORDER_PASSWORD",
    "JIBRI_XMPP_PASSWORD"
]
for secret in NEEDED_SECRETS_WITH_SIMILAR_REQUIREMENTS:
  if not secret in current_secret:
    needs_update = True
    cmd = "random_value=\$(seed=\$(date +%s%N); tr -dc '[:alnum:]' < /dev/urandom | head -c 16; echo \$seed | sha256sum | awk '{print substr(\$1, 1, 16)}'); echo \$random_value"
    output = subprocess.run(cmd, stdout=subprocess.PIPE, shell=True).stdout.decode('utf-8').strip()
    current_secret[secret] = output
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

# post install steps
curl -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_POSTINSTALL"
chmod +x "$SCRIPT_POSTINSTALL"
./"$SCRIPT_POSTINSTALL"
rm $SCRIPT_POSTINSTALL
