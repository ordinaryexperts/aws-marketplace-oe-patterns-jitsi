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
# Jibri configuration
#
apt -y install linux-image-extra-virtual
ufw status
=> “Active or inactive does not matter”
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 10000:60000/tcp
ufw allow 10000:60000/udp
ufw allow 5222
ufw allow 5347
apt -y install linux-image-extra-virtual
sed /GRUB_DEFAULT=0/GRUB_DEFAULT="1>2"/ /etc/default/grub
sed -e 's/GRUB_DEFAULT=0/GRUB_DEFAULT="1>2"/g' /etc/default/grub >> /etc/default/grub_new
mv /etc/default/grub_new /etc/default/grub

update-grub

echo "snd-aloop" >> /etc/modules 

curl -sS -o - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
apt-get -y update
apt-get -y install google-chrome-stable

CHROME_DRIVER_VERSION=`curl -sS chromedriver.storage.googleapis.com/LATEST_RELEASE`
wget -N http://chromedriver.storage.googleapis.com/$CHROME_DRIVER_VERSION/chromedriver_linux64.zip -P ~/
unzip ~/chromedriver_linux64.zip -d ~/
rm ~/chromedriver_linux64.zip
sudo mv -f ~/chromedriver /usr/local/bin/chromedriver
sudo chown root:root /usr/local/bin/chromedriver
sudo chmod 0755 /usr/local/bin/chromedriver

apt-get -y install default-jre-headless ffmpeg curl alsa-utils icewm xdotool xserver-xorg-input-void xserver-xorg-video-dummy


# Install Jibri
wget -qO - https://download.jitsi.org/jitsi-key.gpg.key | sudo apt-key add - 
sudo sh -c "echo 'deb https://download.jitsi.org stable/' > /etc/apt/sources.list.d/jitsi-stable.list"
sudo apt-get -y update 
sudo apt-get -y install jibri    

mkdir /srv/recordings
chown jibri:jitsi /srv/recordings
HOST_TO_USE=${JitsiHostname}
## Write custom config
cp /etc/jitsi/jibri/jibri.conf /etc/jitsi/jibri/jibri.conf.old
AUTH_PASS=${JibriAuthPass}
RECORDER_PASS=${JibriRecorderPass}
cat << EOF > /etc/jitsi/jibri/jibri.conf
jibri {
      api {
        xmpp {
            environments = [
                {
                  xmpp_server_hosts = [
                    "${HOST_TO_USE}"
                  ]
                  xmpp_domain = "${HOST_TO_USE}"
                  control_login {
                    domain = "auth.${HOST_TO_USE}",
                    username = "jibri",
                    password ="${AUTH_PASS}"
                  }
                  control_muc {
                      domain = "internal.auth.${HOST_TO_USE}",
                      room_name = "JibriBrewery",
                      nickname = "jibri-raj"
                  }
                  call_login {
                      domain = "recorder.${HOST_TO_USE}",
                      username = "recorder",
                      password = "${RECORDER_PASS}"
                  }
                }
            ]
        }
    }
}
EOF

systemctl restart jibri   
systemctl status jibri 
#
# cloudformation signal
#
sudo usermod -aG adm,audio,video,plugdev jibri 


cfn-signal --exit-code $success --stack ${AWS::StackName} --resource JitsiAsg --region ${AWS::Region}

# Reboot Jibri instance
# reboot
