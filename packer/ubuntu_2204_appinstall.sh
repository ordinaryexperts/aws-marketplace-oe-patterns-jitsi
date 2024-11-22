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

# https://github.com/jitsi/docker-jitsi-meet/releases/tag/stable-9779 10/22/2024
JITSI_VERSION=stable-9779

cd /root

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

cat <<EOF > /root/append-config.py
#!/usr/bin/env python3

import json
import os
with open('/opt/oe/patterns/instance.json', 'r') as file:
    data = json.load(file)
for key, value in data.items():
    try:
        file_path, varname = key.split(':')
        # Check if file_path is a .js file
        if os.path.splitext(file_path)[1] == '.js':
            if file_path == 'interface_config.js':
                output = f'interfaceConfig.{varname} = "{value}";'
            elif file_path == 'config.js':
                output = f'config.{varname} = "{value}";'
            else:
                output = f'{varname} = "{value}";'
            file_path = f'/s3/jitsi-meet-cfg/web/custom-{file_path}'
        else:
            output = f'{varname}={value}'
            file_path = f'/root/jitsi-docker-jitsi-meet/{file_path}'
        # Ensure the directory exists
        directory = os.path.dirname(file_path)
        if directory and not os.path.exists(directory):
            os.makedirs(directory)
        # Check if file exists, if not create it
        if not os.path.exists(file_path):
            with open(file_path, 'w') as f:
                pass  # Just create the file
        # Append the output to the file
        with open(file_path, 'a') as f:
            f.write(output + '\n')
    except Exception as e:
        print(f'Error processing key {key}: {e}')
EOF
chown root:root /root/append-config.py
chmod 744 /root/append-config.py

# post install steps
curl -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_POSTINSTALL"
chmod +x "$SCRIPT_POSTINSTALL"
./"$SCRIPT_POSTINSTALL"
rm $SCRIPT_POSTINSTALL
