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
          
cfn-signal --exit-code $? --stack ${AWS::StackName} --resource JitsiAsg --region ${AWS::Region}
