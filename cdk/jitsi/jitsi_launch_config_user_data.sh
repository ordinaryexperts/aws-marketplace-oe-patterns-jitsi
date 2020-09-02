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

#
# Jitsi configuration
#

# setup FQDN *before* install
echo "127.0.0.1 ${JitsiHostname}" >> /etc/hosts

# preselect install questions
echo "jitsi-videobridge2 jitsi-videobridge/jvb-hostname string ${JitsiHostname}" | debconf-set-selections
echo "jitsi-meet-web-config jitsi-meet/cert-choice select Generate a new self-signed certificate (You will later get a chance to obtain a Let's encrypt certificate)" | debconf-set-selections

apt-get -y install jitsi-meet

# generate Let's Encrypt certificate
printf "${LetsEncryptCertificateEmail}\n" | /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh

# configure behind NAT Gateway?
#sed -i 's/^org.ice4j.ice.harvest.STUN_MAPPING_HARVESTER_ADDRESSES/#&/' /etc/jitsi/videobridge/sip-communicator.properties
#LOCAL_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
#PUBLIC_IP=$(curl http://icanhzip.com)
#echo "org.ice4j.ice.harvest.NAT_HARVESTER_LOCAL_ADDRESS=$LOCAL_IP" >> /etc/jitsi/videobridge/sip-communicator.properties
#echo "org.ice4j.ice.harvest.NAT_HARVESTER_PUBLIC_ADDRESS=$PUBLIC_IP" >> /etc/jitsi/videobridge/sip-communicator.properties

# raise systemd limits
sed -i 's/#DefaultLimitNOFILE=/DefaultLimitNOFILE=65000/g' /etc/systemd/system.conf
sed -i 's/#DefaultLimitNPROC=/DefaultLimitNPROC=65000/g' /etc/systemd/system.conf
sed -i 's/#DefaultTasksMax=/DefaultTasksMax=65000/g' /etc/systemd/system.conf

systemctl daemon-reload
systemctl restart jitsi-videobridge2
systemctl restart apache2
