SCRIPT_VERSION=1.3.0
SCRIPT_PREINSTALL=ubuntu_2004_2204_preinstall.sh
SCRIPT_POSTINSTALL=ubuntu_2004_2204_postinstall.sh

# preinstall steps
curl -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_PREINSTALL"
chmod +x $SCRIPT_PREINSTALL
./$SCRIPT_PREINSTALL
rm $SCRIPT_PREINSTALL

#
# Jitsi configuration
#  * https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-quickstart
#

# ruby
apt-get install -y fonts-lato libruby3.0 rake ruby ruby-hocon ruby-net-telnet ruby-rubygems ruby-webrick ruby-xmlrpc ruby3.0 rubygems-integration

# libunbound
apt-get install -y libevent-2.1.7 libunbound8

# Pin down a specific version
# as of 2023-07-07, this is the latest stable release
# https://jitsi.org/blog/jitsi-meet-stable-releases-now-more-discoverable/
# apt-cache madison jitsi-meet
VERSION='2.0.8719-1'
apt-get -y install apache2 debconf-utils gnupg2 uuid-runtime
apt install apt-transport-https

# disable default site
a2dissite 000-default

# prosody 0.11
wget https://prosody.im/files/prosody-debian-packages.key -O- | apt-key add -
echo deb http://packages.prosody.im/debian $(lsb_release -sc) main | tee -a /etc/apt/sources.list.d/prosody-dev.list > /dev/null

# jitsi
curl -sL https://download.jitsi.org/jitsi-key.gpg.key | gpg --dearmor | tee /usr/share/keyrings/jitsi-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/" | tee /etc/apt/sources.list.d/jitsi-stable.list > /dev/null
apt-get update
rm -rf /var/cache/apt/archives/*.deb
apt-get -y install --download-only jitsi-meet=${VERSION}

mkdir /root/jitsi-debs
mv /var/cache/apt/archives/*.deb /root/jitsi-debs

# not configuring firewall with ufw in favor of AWS security groups

# post install steps
curl -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_POSTINSTALL"
chmod +x "$SCRIPT_POSTINSTALL"
./"$SCRIPT_POSTINSTALL"
rm $SCRIPT_POSTINSTALL
