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
dpkg -i /root/jitsi-debs/lua*.deb
dpkg -i /root/jitsi-debs/ruby*.deb
dpkg -i /root/jitsi-debs/prosody*.deb
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

mkdir -p /opt/oe/patterns/jitsi

# Turn off warnings about scripted control in Chrome:
mkdir -p /etc/opt/chrome/policies/managed/
echo '{ "CommandLineFlagSecurityWarningsEnabled": false }' >>/etc/opt/chrome/policies/managed/managed_policies.json

# secretsmanager
SECRET_ARN="${SecretArn}"
AUTH_KEY="${Prefix}_JIBRI_AUTH_PASS"
RECORDER_KEY="${Prefix}_JIBRI_RECORDER_PASS"
AUTH_VAL=`aws secretsmanager get-secret-value --secret-id $AUTH_KEY | jq '.SecretString | fromjson | .value' | sed "s/\"/'/g"`
RECORDER_VAL=`aws secretsmanager get-secret-value --secret-id $RECORDER_KEY | jq '.SecretString | fromjson | .value' | sed "s/\"/'/g"`
#
# customize Jitsi interface
#
INTERFACE_CONFIG=/usr/share/jitsi-meet/interface_config.js
JITSI_IMAGE_DIR=/usr/share/jitsi-meet/images
cp $INTERFACE_CONFIG $INTERFACE_CONFIG.default
echo "// Ordinary Experts Jitsi Patterns config overrides" >> $INTERFACE_CONFIG
echo "interfaceConfig.APP_NAME = '${JitsiInterfaceAppName}';" >> $INTERFACE_CONFIG
echo "interfaceConfig.DEFAULT_LOGO_URL = '${JitsiInterfaceBrandWatermark}';" >> $INTERFACE_CONFIG
echo "interfaceConfig.DEFAULT_REMOTE_DISPLAY_NAME = '${JitsiInterfaceDefaultRemoteDisplayName}';" >> $INTERFACE_CONFIG
echo "interfaceConfig.DEFAULT_WELCOME_PAGE_LOGO_URL = '${JitsiInterfaceBrandWatermark}';" >> $INTERFACE_CONFIG
echo "interfaceConfig.NATIVE_APP_NAME = '${JitsiInterfaceNativeAppName}';" >>  $INTERFACE_CONFIG
echo "interfaceConfig.SHOW_BRAND_WATERMARK = ${JitsiInterfaceShowBrandWatermark};" >> $INTERFACE_CONFIG
echo "interfaceConfig.SHOW_WATERMARK_FOR_GUESTS = ${JitsiInterfaceShowWatermarkForGuests};" >> $INTERFACE_CONFIG
echo "interfaceConfig.TOOLBAR_BUTTONS = [ 'microphone', 'camera', 'closedcaptions', 'desktop', 'embedmeeting', 'fullscreen', 'fodeviceselection', 'hangup', 'profile', 'chat', 'etherpad', 'sharedvideo', 'settings', 'raisehand', 'videoquality', 'filmstrip', 'invite', 'feedback', 'stats', 'shortcuts', 'tileview', 'videobackgroundblur', 'download', 'help', 'mute-everyone', 'security' ];" >> $INTERFACE_CONFIG
echo "interfaceConfig.fileRecordingsEnabled = true;" >> $INTERFACE_CONFIG

CONFIG=/usr/share/jitsi-meet/config.js
cp $CONFIG $CONFIG.default
echo "config.liveStreamingEnabled = true;" >> $CONFIG

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

cat << EOF > /etc/jitsi/jibri/jibri_setup.lua
## Setup Jibri config 
plugin_paths = { "/usr/share/jitsi-meet/prosody-plugins/" }

-- domain mapper options, must at least have domain base set to use the mapper
muc_mapper_domain_base = "${JitsiHostname}";

turncredentials_secret = "m5Zw2rB5kyDhjYuQ";

turncredentials = {
    { type = "stun", host = "${JitsiHostname}", port = "3478" },
    { type = "turn", host = "${JitsiHostname}", port = "3478", transport = "udp" },
    { type = "turns", host = "${JitsiHostname}", port = "5349", transport = "tcp" }
};

cross_domain_bosh = false;
consider_bosh_secure = true;
-- https_ports = { }; -- Remove this line to prevent listening on port 5284

-- https://ssl-config.mozilla.org/#server=haproxy&version=2.1&config=intermediate&openssl=1.1.0g&guideline=5.4
ssl = {
    protocol = "tlsv1_2+";
    ciphers = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384"
}

VirtualHost "${JitsiHostname}"
    -- enabled = false -- Remove this line to enable this host
    authentication = "anonymous"
    -- Properties below are modified by jitsi-meet-tokens package config
    -- and authentication above is switched to "token"
    --app_id="example_app_id"
    --app_secret="example_app_secret"
    -- Assign this host a certificate for TLS, otherwise it would use the one
    -- set in the global section (if any).
    -- Note that old-style SSL on port 5223 only supports one certificate, and will always
    -- use the global one.
    ssl = {
        key = "/etc/prosody/certs/${JitsiHostname}.key";
        certificate = "/etc/prosody/certs/${JitsiHostname}.crt";
    }
    speakerstats_component = "speakerstats.${JitsiHostname}"
    conference_duration_component = "conferenceduration.${JitsiHostname}"
    -- we need bosh
    modules_enabled = {
        "bosh";
        "pubsub";
        "ping"; -- Enable mod_ping
        "speakerstats";
        "turncredentials";
        "conference_duration";
        "muc_lobby_rooms";
    }
    c2s_require_encryption = false
    lobby_muc = "lobby.${JitsiHostname}"
    main_muc = "conference.${JitsiHostname}"
    -- muc_lobby_whitelist = { "recorder.${JitsiHostname}" } -- Here we can whitelist jibri to enter lobby enabled rooms

Component "conference.${JitsiHostname}" "muc"
    storage = "none"
    modules_enabled = {
        "muc_meeting_id";
        "muc_domain_mapper";
        --"token_verification";
    }
    admins = { "focus@auth.${JitsiHostname}" }
    muc_room_locking = false
    muc_room_default_public_jids = true

-- internal muc component
Component "internal.auth.${JitsiHostname}" "muc"
    storage = "null"
    modules_enabled = {
        "ping";
    }
    admins = { "focus@auth.${JitsiHostname}", "jvb@auth.${JitsiHostname}" }
    muc_room_locking = false
    muc_room_default_public_jids = true
    muc_room_cache_size = 1000

VirtualHost "auth.${JitsiHostname}"
    ssl = {
        key = "/etc/prosody/certs/auth.${JitsiHostname}.key";
        certificate = "/etc/prosody/certs/auth.${JitsiHostname}.crt";
    }
    authentication = "internal_plain"

VirtualHost "recorder.${JitsiHostname}"
  modules_enabled = {
    "ping";
  }
  authentication = "internal_plain"

Component "focus.${JitsiHostname}"
    component_secret = "Bb@1@sMc"

Component "speakerstats.${JitsiHostname}" "speakerstats_component"
    muc_component = "conference.${JitsiHostname}"

Component "conferenceduration.${JitsiHostname}" "conference_duration_component"
    muc_component = "conference.${JitsiHostname}"

Component "lobby.${JitsiHostname}" "muc"
    storage = "none"
    restrict_room_creation = true
    muc_room_locking = false
    muc_room_default_public_jids = true
EOF
cp "/etc/jitsi/jibri/${JitsiHostname}.cfg.lua" "/etc/jitsi/jibri/${JitsiHostname}.old.cfg.lua"
mv "/etc/jitsi/jibri/jibri_setup.lua" "/etc/jitsi/jibri/${JitsiHostname}.cfg.lua"

### Change from here ###
# Configure Prosody
sed -i "s/--Component \"conference.example.com\" \"muc\"/Component \"conference.${JitsiHostname}\" \"muc\"\n--- Store MUC messages in an archive and allow users to access it\nmodules_enabled = { \"muc_mam\" }/g" /etc/prosody/prosody.cfg.lua
#echo "--- internal muc component, meant to enable pools of jibri and jigasi clients" >> /etc/prosody/prosody.cfg.lua
#echo "Component \"internal.auth.jitsi.example.com\" \"muc\"" >> /etc/prosody/prosody.cfg.lua
cat <<EOF >> /etc/prosody/prosody.cfg.lua
--- internal muc component, meant to enable pools of jibri and jigasi clients
Component "internal.auth.${JitsiHostname}" "muc"
modules_enabled = {
  "ping";
}
storage = "internal"
muc_room_cache_size = 1000

VirtualHost "recorder.${JitsiHostname}"
modules_enabled = {
  "ping";
}
authentication = "internal_plain"
EOF

#Create two new accounts for Jibri to use (one for control purposes, one for recording purposes):
prosodyctl register jibri "auth.${JitsiHostname}" "${JibriAuthPass}"
prosodyctl register recorder "recorder.${JitsiHostname}" "${JibriRecorderPass}"

#Configure Jicofo
#Jibri control room and timeout
echo "org.jitsi.jicofo.jibri.BREWERY=JibriBrewery@internal.auth.${JitsiHostname}" >> /etc/jitsi/jicofo/sip-communicator.properties
echo "org.jitsi.jicofo.jibri.PENDING_TIMEOUT=90" >> /etc/jitsi/jicofo/sip-communicator.properties

#Configure Jitsi Meet --> Remove duplicate
sed -i "s/.*fileRecordingsEnabled.*/fileRecordingsEnabled: true,/g" /etc/jitsi/meet/${JitsiHostname}-config.js
sed -i "s/.*liveStreamingEnabled.*/liveStreamingEnabled: true,\nhiddenDomain: \"recorder.${JitsiHostname}\",/g" /etc/jitsi/meet/${JitsiHostname}-config.js

#Store recordings and set its permissions appropriately
mkdir /srv/recordings
chown jibri:jibri /srv/recordings

#Configure Jibri
cat <<EOF >> /etc/jitsi/jibri/config.json
{
  "recording_directory":"/srv/recordings",
  "finalize_recording_script_path": "/recordings/put2s3.sh",
  "xmpp_environments": [
    {
      "name": "prod environment",
      "xmpp_server_hosts": [
        "${JitsiHostname}"
      ],
      "xmpp_domain": "${JitsiHostname}",
      "control_login": {
        // The domain to use for logging in
        "domain": "auth.${JitsiHostname}",
        // The credentials for logging in
        "username": "jibri",
        "password": "${JibriAuthPass}"
      },
      "control_muc": {
        "domain": "internal.${JitsiHostname}",
        "room_name": "JibriBrewery",
        "nickname": "jibri"
      },
      "call_login": {
        "domain": "recorder.${JitsiHostname}",
        "username": "recorder",
        "password": "${JibriRecorderPass}"
      },
      "room_jid_domain_string_to_strip_from_start": "conference.",
      "usage_timeout": "100"
    }
  ]
}
EOF

#Install Java 8
wget -O - https://adoptopenjdk.jfrog.io/adoptopenjdk/api/gpg/key/public | sudo apt-key add -
add-apt-repository https://adoptopenjdk.jfrog.io/adoptopenjdk/deb/
apt update
apt install -y adoptopenjdk-8-hotspot

#Configure Jibri to start with Java 8 instead of the default Java version (replace the word "java" with the full path to Java 8):
sed -i "s/exec java/exec \/usr\/lib\/jvm\/adoptopenjdk-8-hotspot-amd64\/bin\/java/g" /opt/jitsi/jibri/launch.sh

#Restart all services, enable and start Jibri
systemctl restart prosody
systemctl restart jicofo
systemctl restart jitsi-videobridge2
systemctl enable --now jibri

##### until here #######

# Update SIP communicator
#echo "org.jitsi.jicofo.jibri.BREWERY=JibriBrewery@internal.auth.${JitsiHostname}\r\norg.jitsi.jicofo.jibri.PENDING_TIMEOUT=90" >> /etc/jitsi/jicofo/sip-communicator.properties

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
