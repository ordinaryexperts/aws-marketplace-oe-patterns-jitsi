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

# preselect Jitsi install questions
echo "jitsi-videobridge2 jitsi-videobridge/jvb-hostname string ${JitsiHostname}" | debconf-set-selections
echo "jitsi-meet-web-config jitsi-meet/cert-choice select Generate a new self-signed certificate (You will later get a chance to obtain a Let's encrypt certificate)" | debconf-set-selections

# jitsi-meet was downloaded but not installed during AMI build...
dpkg -i /root/jitsi-debs/lib*.deb
dpkg -i /root/jitsi-debs/lua*.deb
dpkg -i /root/jitsi-debs/prosody*.deb
dpkg -i /root/jitsi-debs/uuid*.deb
dpkg -i /root/jitsi-debs/jitsi-videobridge*.deb
dpkg -i /root/jitsi-debs/ji*.deb

# configure Jitsi behind NAT Gateway
JVB_CONFIG=/etc/jitsi/videobridge/sip-communicator.properties
sed -i 's/^org.ice4j.ice.harvest.STUN_MAPPING_HARVESTER_ADDRESSES/#&/' $JVB_CONFIG
LOCAL_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP="${JitsiPublicIP}"
echo "org.ice4j.ice.harvest.NAT_HARVESTER_LOCAL_ADDRESS=$LOCAL_IP" >> $JVB_CONFIG
echo "org.ice4j.ice.harvest.NAT_HARVESTER_PUBLIC_ADDRESS=$PUBLIC_IP" >> $JVB_CONFIG

# raise systemd limits
sed -i 's/#DefaultLimitNOFILE=/DefaultLimitNOFILE=65000/g' /etc/systemd/system.conf
sed -i 's/#DefaultLimitNPROC=/DefaultLimitNPROC=65000/g' /etc/systemd/system.conf
sed -i 's/#DefaultTasksMax=/DefaultTasksMax=65000/g' /etc/systemd/system.conf

systemctl daemon-reload
systemctl restart jitsi-videobridge2

#
# customize Jitsi interface
#

INTERFACE_CONFIG=/usr/share/jitsi-meet/interface_config.js
JITSI_IMAGE_DIR=/usr/share/jitsi-meet/images
cp $INTERFACE_CONFIG $INTERFACE_CONFIG.default
echo "// Ordinary Experts Jitsi Patterns config overrides" >> $INTERFACE_CONFIG
echo "interfaceConfig.NATIVE_APP_NAME = '${JitsiInterfaceNativeAppName}';" >>  $INTERFACE_CONFIG
echo "interfaceConfig.APP_NAME = '${JitsiInterfaceAppName}';" >> $INTERFACE_CONFIG
echo "interfaceConfig.DEFAULT_REMOTE_DISPLAY_NAME = '${JitsiInterfaceDefaultRemoteDisplayName}';" >> $INTERFACE_CONFIG
echo "interfaceConfig.SHOW_BRAND_WATERMARK = ${JitsiInterfaceShowBrandWatermark};" >> $INTERFACE_CONFIG
echo "interfaceConfig.SHOW_WATERMARK_FOR_GUESTS = ${JitsiInterfaceShowWatermarkForGuests};" >> $INTERFACE_CONFIG
CONFIG=/usr/share/jitsi-meet/config.js
cp $CONFIG $CONFIG.default
echo "// Ordinary Experts Jitsi Patterns config overrides" >> $CONFIG

echo "config.toolbarButtons=['microphone','camera','closedcaptions','desktop','embedmeeting','fullscreen','fodeviceselection','hangup','profile','chat','livestreaming','etherpad','sharedvideo','settings','raisehand','videoquality','filmstrip','invite','feedback','stats','shortcuts','tileview','select-background','download','help','mute-everyone','mute-video-everyone','security'];" >>  $CONFIG
# brand watermark image
JITSI_BRAND_WATERMARK=${JitsiInterfaceBrandWatermark}
if [ ! -z "$JITSI_BRAND_WATERMARK" ];
then
    wget -O $JITSI_IMAGE_DIR/rightwatermark.png $JITSI_BRAND_WATERMARK
fi
echo "interfaceConfig.BRAND_WATERMARK_LINK = '${JitsiInterfaceBrandWatermarkLink}';" >> $INTERFACE_CONFIG
# watermark image
JITSI_WATERMARK=${JitsiInterfaceWatermark}
if [ ! -z "$JITSI_WATERMARK" ];
then
    cp $JITSI_IMAGE_DIR/watermark.png $JITSI_IMAGE_DIR/watermark.default.png
    wget -O $JITSI_IMAGE_DIR/watermark.png $JITSI_WATERMARK
fi
echo "interfaceConfig.JITSI_WATERMARK_LINK = '${JitsiInterfaceWatermarkLink}';" >> $INTERFACE_CONFIG
systemctl restart apache2

#
# associate EIP
#

# error handling
function error_exit
{
    cfn-signal --exit-code 1 --stack ${AWS::StackName} --resource JitsiAsg --region ${AWS::Region}
    exit 1
}

instance_id=$(curl http://169.254.169.254/latest/meta-data/instance-id)
max_attach_tries=12
attach_tries=0
success=1
while [[ $success != 0 ]]; do
    if [ $attach_tries -gt $max_attach_tries ]; then
        error_exit
    fi
    sleep 10
    echo aws ec2 associate-address --region ${AWS::Region} --instance-id $instance_id --allocation-id ${Eip.AllocationId}
    aws ec2 associate-address --region ${AWS::Region} --instance-id $instance_id --allocation-id ${Eip.AllocationId}
    success=$?
    ((attach_tries++))
done

# generate Let's Encrypt certificate
#   https://stackoverflow.com/questions/57904900/aws-cloudformation-template-with-letsencrypt-ssl-certificate
LETSENCRYPTEMAIL="${LetsEncryptCertificateEmail}"
if [ -z "$LETSENCRYPTEMAIL" ]; then
    # no Let's Encrypt email - modify the install script not to use it
    sed -i 's/--agree-tos --email $EMAIL/--agree-tos --register-unsafely-without-email/g' /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh
    LETSENCRYPTEMAIL="dummy@example.com"
fi

while true; do
    printf "$LETSENCRYPTEMAIL\n" | /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh

    if [ $? -eq 0 ]
    then
        echo "LetsEncrypt success"
        break
    else
        echo "Retry..."
        # https://letsencrypt.org/docs/rate-limits/
        sleep 30
    fi
done
systemctl restart apache2
success=$?

#
# cloudformation signal
#

cfn-signal --exit-code $success --stack ${AWS::StackName} --resource JitsiAsg --region ${AWS::Region}
