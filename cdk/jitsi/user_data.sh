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

# TODO: why isn't this working in the AMI
apt-get update && apt-get -y install s3fs

mkdir /s3
echo 's3fs#${AssetsBucket} /s3 fuse _netdev,allow_other,iam_role=auto 0 0' >> /etc/fstab
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

cat <<EOF > /root/jitsi-docker-jitsi-meet/.env
CONFIG=/s3/jitsi-meet-cfg
HTTP_PORT=80
HTTPS_PORT=443
TZ=UTC
PUBLIC_URL=https://${Hostname}
JVB_ADVERTISE_IPS=$ip1,$ip2
ENABLE_LETSENCRYPT=0
# XMPP password for Jicofo client connections
JICOFO_AUTH_PASSWORD=$JICOFO_AUTH_PASSWORD
# XMPP password for JVB client connections
JVB_AUTH_PASSWORD=$JVB_AUTH_PASSWORD
# XMPP password for Jigasi MUC client connections
JIGASI_XMPP_PASSWORD=$JIGASI_XMPP_PASSWORD
# XMPP recorder password for Jibri client connections
JIBRI_RECORDER_PASSWORD=$JIBRI_RECORDER_PASSWORD
# XMPP password for Jibri client connections
JIBRI_XMPP_PASSWORD=$JIBRI_XMPP_PASSWORD
EOF

cat <<EOF > /root/start.sh
#!/usr/bin/env bash
cd /root/jitsi-docker-jitsi-meet
docker compose up -d
EOF
cat <<EOF > /root/stop.sh
#!/usr/bin/env bash
cd /root/jitsi-docker-jitsi-meet
docker compose down
EOF
cat <<EOF > /root/restart.sh
#!/usr/bin/env bash
cd /root/jitsi-docker-jitsi-meet
docker compose restart
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
systemctl enable jitsi.service
systemctl start jitsi.service
success=$?

# TODO
# #
# # customize Jitsi interface
# #

# INTERFACE_CONFIG=/usr/share/jitsi-meet/interface_config.js
# JITSI_IMAGE_DIR=/usr/share/jitsi-meet/images
# cp $INTERFACE_CONFIG $INTERFACE_CONFIG.default
# echo "// Ordinary Experts Jitsi Patterns config overrides" >> $INTERFACE_CONFIG
# echo "interfaceConfig.APP_NAME = '${JitsiInterfaceAppName}';" >> $INTERFACE_CONFIG
# if [[ ! -z "${JitsiInterfaceBrandWatermark}" ]]; then
#     echo "interfaceConfig.DEFAULT_LOGO_URL = '${JitsiInterfaceBrandWatermark}';" >> $INTERFACE_CONFIG
# fi
# echo "interfaceConfig.DEFAULT_REMOTE_DISPLAY_NAME = '${JitsiInterfaceDefaultRemoteDisplayName}';" >> $INTERFACE_CONFIG
# if [[ ! -z "${JitsiInterfaceBrandWatermark}" ]]; then
#     echo "interfaceConfig.DEFAULT_WELCOME_PAGE_LOGO_URL = '${JitsiInterfaceBrandWatermark}';" >> $INTERFACE_CONFIG
# fi
# echo "interfaceConfig.NATIVE_APP_NAME = '${JitsiInterfaceNativeAppName}';" >>  $INTERFACE_CONFIG
# echo "interfaceConfig.SHOW_BRAND_WATERMARK = ${JitsiInterfaceShowBrandWatermark};" >> $INTERFACE_CONFIG
# echo "interfaceConfig.SHOW_WATERMARK_FOR_GUESTS = ${JitsiInterfaceShowWatermarkForGuests};" >> $INTERFACE_CONFIG
# echo "interfaceConfig.TOOLBAR_BUTTONS = [ 'microphone', 'camera', 'closedcaptions', 'desktop', 'embedmeeting', 'fullscreen', 'fodeviceselection', 'hangup', 'profile', 'chat', 'etherpad', 'sharedvideo', 'settings', 'raisehand', 'videoquality', 'filmstrip', 'invite', 'feedback', 'stats', 'shortcuts', 'tileview', 'videobackgroundblur', 'download', 'help', 'mute-everyone', 'security' ];" >> $INTERFACE_CONFIG
# echo "interfaceConfig.DISABLE_VIDEO_BACKGROUND = true;" >> $INTERFACE_CONFIG

# # brand watermark image
# JITSI_BRAND_WATERMARK=${JitsiInterfaceBrandWatermark}
# if [ ! -z "$JITSI_BRAND_WATERMARK" ];
# then
#     wget -O $JITSI_IMAGE_DIR/rightwatermark.png $JITSI_BRAND_WATERMARK
# fi
# echo "interfaceConfig.BRAND_WATERMARK_LINK = '${JitsiInterfaceBrandWatermarkLink}';" >> $INTERFACE_CONFIG
# # watermark image
# JITSI_WATERMARK=${JitsiInterfaceWatermark}
# if [ ! -z "$JITSI_WATERMARK" ];
# then
#     cp $JITSI_IMAGE_DIR/watermark.png $JITSI_IMAGE_DIR/watermark.default.png
#     wget -O $JITSI_IMAGE_DIR/watermark.png $JITSI_WATERMARK
# fi
# echo "interfaceConfig.JITSI_WATERMARK_LINK = '${JitsiInterfaceWatermarkLink}';" >> $INTERFACE_CONFIG

# sed -i 's/server_names_hash_bucket_size 64;/server_names_hash_bucket_size 128;/g' /etc/nginx/sites-available/${Hostname}.conf
# sed -i '\|root /usr/share/jitsi-meet;|a \
# \
#     location = /elb-check {\
#         access_log off;\
#         return 200 '\''ok'\'';\
#         add_header Content-Type text/plain;\
#     }\
# ' /etc/nginx/sites-available/${Hostname}.conf
# rm -f /etc/nginx/sites-enabled/default

#
# cloudformation signal
#

cfn-signal --exit-code $success --stack ${AWS::StackName} --resource Asg --region ${AWS::Region}
