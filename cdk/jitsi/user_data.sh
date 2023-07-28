#!/bin/bash

# aws cloudwatch
sed -i 's/ASG_APP_LOG_GROUP_PLACEHOLDER/${AsgAppLogGroup}/g' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
sed -i 's/ASG_SYSTEM_LOG_GROUP_PLACEHOLDER/${AsgSystemLogGroup}/g' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
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
echo "jitsi-meet-web-config jitsi-meet/jaas-choice boolean false" | debconf-set-selections

# jitsi-meet was downloaded but not installed during AMI build...
dpkg -i /root/jitsi-debs/lua*.deb
dpkg -i /root/jitsi-debs/prosody*.deb
dpkg -i /root/jitsi-debs/jitsi-videobridge*.deb
dpkg -i /root/jitsi-debs/jitsi-meet-web-config*.deb
dpkg -i /root/jitsi-debs/*.deb

# raise systemd limits
sed -i 's/^#DefaultLimitNOFILE=.*$/DefaultLimitNOFILE=65000/' /etc/systemd/system.conf
sed -i 's/^#DefaultLimitNPROC=.*$/DefaultLimitNPROC=65000/' /etc/systemd/system.conf
sed -i 's/^#DefaultTasksMax=.*$/DefaultTasksMax=65000/' /etc/systemd/system.conf

# prosody fix
chown prosody:prosody /etc/prosody/certs/localhost.key
service prosody restart
service jicofo restart

systemctl daemon-reload
systemctl restart jitsi-videobridge2

#
# customize Jitsi interface
#

INTERFACE_CONFIG=/usr/share/jitsi-meet/interface_config.js
JITSI_IMAGE_DIR=/usr/share/jitsi-meet/images
cp $INTERFACE_CONFIG $INTERFACE_CONFIG.default
echo "// Ordinary Experts Jitsi Patterns config overrides" >> $INTERFACE_CONFIG
echo "interfaceConfig.APP_NAME = '${JitsiInterfaceAppName}';" >> $INTERFACE_CONFIG
if [[ ! -z "${JitsiInterfaceBrandWatermark}" ]]; then
    echo "interfaceConfig.DEFAULT_LOGO_URL = '${JitsiInterfaceBrandWatermark}';" >> $INTERFACE_CONFIG
fi
echo "interfaceConfig.DEFAULT_REMOTE_DISPLAY_NAME = '${JitsiInterfaceDefaultRemoteDisplayName}';" >> $INTERFACE_CONFIG
if [[ ! -z "${JitsiInterfaceBrandWatermark}" ]]; then
    echo "interfaceConfig.DEFAULT_WELCOME_PAGE_LOGO_URL = '${JitsiInterfaceBrandWatermark}';" >> $INTERFACE_CONFIG
fi
echo "interfaceConfig.NATIVE_APP_NAME = '${JitsiInterfaceNativeAppName}';" >>  $INTERFACE_CONFIG
echo "interfaceConfig.SHOW_BRAND_WATERMARK = ${JitsiInterfaceShowBrandWatermark};" >> $INTERFACE_CONFIG
echo "interfaceConfig.SHOW_WATERMARK_FOR_GUESTS = ${JitsiInterfaceShowWatermarkForGuests};" >> $INTERFACE_CONFIG
echo "interfaceConfig.TOOLBAR_BUTTONS = [ 'microphone', 'camera', 'closedcaptions', 'desktop', 'embedmeeting', 'fullscreen', 'fodeviceselection', 'hangup', 'profile', 'chat', 'etherpad', 'sharedvideo', 'settings', 'raisehand', 'videoquality', 'filmstrip', 'invite', 'feedback', 'stats', 'shortcuts', 'tileview', 'videobackgroundblur', 'download', 'help', 'mute-everyone', 'security' ];" >> $INTERFACE_CONFIG

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

sed -i 's/server_names_hash_bucket_size 64;/server_names_hash_bucket_size 128;/g' /etc/nginx/sites-available/${JitsiHostname}.conf
sed -i '\|root /usr/share/jitsi-meet;|a \
\
    location = /elb-check {\
        access_log off;\
        return 200 '\''ok'\'';\
        add_header Content-Type text/plain;\
    }\
' /etc/nginx/sites-available/${JitsiHostname}.conf
rm -f /etc/nginx/sites-enabled/default

systemctl restart nginx
success=$?

#
# cloudformation signal
#

cfn-signal --exit-code $success --stack ${AWS::StackName} --resource Asg --region ${AWS::Region}
