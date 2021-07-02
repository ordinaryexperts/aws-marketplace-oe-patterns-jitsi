#!/bin/bash

# aws cloudwatch
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
      "ImageId": "\${!aws:ImageId}",
      "InstanceId": "\${!aws:InstanceId}",
      "InstanceType": "\${!aws:InstanceType}",
      "AutoScalingGroupName": "\${!aws:AutoScalingGroupName}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "log_group_name": "${JitsiSystemLogGroup}",
            "log_stream_name": "{instance_id}-/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/dpkg.log",
            "log_group_name": "${JitsiSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/dpkg.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apt/history.log",
            "log_group_name": "${JitsiSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/apt/history.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init.log",
            "log_group_name": "${JitsiSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/cloud-init.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "${JitsiSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/cloud-init-output.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "${JitsiSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/auth.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "${JitsiSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/syslog",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/amazon/ssm/amazon-ssm-agent.log",
            "log_group_name": "${JitsiSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/amazon/ssm/amazon-ssm-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/amazon/ssm/errors.log",
            "log_group_name": "${JitsiSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/amazon/ssm/errors.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/jitsi/jicofo.log",
            "log_group_name": "${JitsiAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/jitsi/jicofo.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/jitsi/jvb.log",
            "log_group_name": "${JitsiAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/jitsi/jvb.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/prosody/prosody.log",
            "log_group_name": "${JitsiAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/prosody/prosody.log",
            "timezone": "UTC"
          }
        ]
      }
    },
    "log_stream_name": "{instance_id}"
  }
}
EOF
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent


# secretsmanager
SECRET_ARN="${SecretArn}"
mkdir -p /opt/oe/patterns/jitsi/
echo $SECRET_ARN >> /opt/oe/patterns/jitsi/secret-arn.txt

SECRET_NAME=$(aws secretsmanager list-secrets --query "SecretList[?ARN=='$SECRET_ARN'].Name" --output text)
echo $SECRET_NAME >> /opt/oe/patterns/jitsi/secret-name.txt

SECRET_KEY="${!PREFIX}_JIBRI_AUTH_PASS"
SECRET_RECORDER_KEY="${!PREFIX}_JIBRI_RECORDER_PASS"
SECRET_AUTH_PASS=$(aws secretsmanager get-secret-value --secret-id ${!SECRET_KEY} | jq '.SecretString | fromjson | .value' | sed "s/\"/'/g"`)
SECRET_RECORDER_PASS=$(aws secretsmanager get-secret-value --secret-id ${!SECRET_RECORDER_KEY} | jq '.SecretString | fromjson | .value' | sed "s/\"/'/g"`)

aws ssm get-parameter \
    --name "/aws/reference/secretsmanager/$SECRET_NAME" \
    --with-decryption \
    --query Parameter.Value \
| jq -r . >> /opt/oe/patterns/jitsi/secret.json
#
# Jibri configuration
#

## Write custom config
cp /etc/jitsi/jibri/jibri.conf /etc/jitsi/jibri/jibri.conf.old
cat << EOF > /etc/jitsi/jibri/jibri.conf
jibri {
      recording {
        recordings-directory = "/srv/recordings"
      }
      api { 
        http {
            internal-api-port = 8001
            external-api-port = 8002
        }
        xmpp {
            environments = [
                {
                  name = "main"
                  xmpp_server_hosts = [ "${JitsiHostname}" ]
                  xmpp_domain = "${JitsiHostname}"
                  control_login {
                    domain = "auth.${JitsiHostname}",
                    username = "jibri",
                    password ="${!SECRET_AUTH_PASS}"
                  }
                  control_muc {
                      domain = "internal.auth.${JitsiHostname}",
                      room_name = "JibriBrewery",
                      nickname = "jibri-raj"
                  }
                  call_login {
                      domain = "recorder.${JitsiHostname}",
                      username = "recorder",
                      password = "${!SECRET_RECORDER_PASS}"
                  }
                }
            ]
        }
    }
}
EOF



systemctl enable jibri
systemctl restart jibri   
success=$?
#
# cloudformation signal
#

cfn-signal --exit-code $success --stack ${AWS::StackName} --resource JibriAsg --region ${AWS::Region}

# Reboot Jibri instance
# reboot
