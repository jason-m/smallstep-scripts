#!/bin/bash
#
# This script will launch and configure a step-ca SSH Certificate Authority
# with OIDC and AWS provisioners
#
# See https://smallstep.com/blog/diy-single-sign-on-for-ssh/ for full instructions

OIDC_CLIENT_ID="[OAuth client ID]" # from Google
OIDC_CLIENT_SECRET="[OAuth client secret]" # from Google
ALLOWED_DOMAIN="[the domain name of accounts your users will use to sign to Google]"
CA_NAME="[A name for your CA]"
ROOT_KEY_PASSWORD="[A password for your CA's root key]"
EMAIL="your@email.address"

OPENID_CONFIG_ENDPOINT="https://accounts.google.com/.well-known/openid-configuration"

curl -sLO https://github.com/smallstep/certificates/releases/download/v0.15.4/step-certificates_0.15.4_amd64.deb
dpkg -i step-certificates_0.15.4_amd64.deb

curl -sLO https://github.com/smallstep/cli/releases/download/v0.15.2/step-cli_0.15.2_amd64.deb
dpkg -i step-cli_0.15.2_amd64.deb

# All your CA config and certificates will go into $STEPPATH.
export STEPPATH=/etc/step-ca
mkdir -p $STEPPATH
chmod 700 $STEPPATH
echo $ROOT_KEY_PASSWORD > $STEPPATH/password.txt

# Add a service to systemd for our CA.
cat<<EOF > /etc/systemd/system/step-ca.service
[Unit]
Description=step-ca service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
Environment=STEPPATH=/etc/step-ca
ExecStart=/usr/bin/step-ca ${STEPPATH}/config/ca.json --password-file=${STEPPATH}/password.txt

[Install]
WantedBy=multi-user.target
EOF

LOCAL_HOSTNAME=`curl -s http://169.254.169.254/latest/meta-data/local-hostname`
LOCAL_IP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
PUBLIC_HOSTNAME=`curl -s http://169.254.169.254/latest/meta-data/public-hostname`
PUBLIC_IP=`curl -s http://169.254.169.254/latest/meta-data/public-ipv4`
AWS_ACCOUNT_ID=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep accountId | awk '{print $3}' | sed  's/"//g' | sed 's/,//g'`

# Set up our basic CA configuration and generate root keys
step ca init --ssh --name="$CA_NAME" \
     --dns="$LOCAL_IP,$LOCAL_HOSTNAME,$PUBLIC_IP,$PUBLIC_HOSTNAME" \
     --address=":443" --provisioner="$EMAIL" \
     --password-file="$STEPPATH/password.txt"

# Add the Google OAuth provisioner, for user certificates
step ca provisioner add Google --type=oidc --ssh \
    --client-id="$OIDC_CLIENT_ID" \
    --client-secret="$OIDC_CLIENT_SECRET" \
    --configuration-endpoint="$OPENID_CONFIG_ENDPOINT" \
    --domain="$ALLOWED_DOMAIN"

# Add the AWS provisioner, for host bootstrapping
step ca provisioner add "Amazon Web Services" --type=AWS --ssh \
    --aws-account=$AWS_ACCOUNT_ID

# The sshpop provisioner lets hosts renew their ssh certificates
step ca provisioner add SSHPOP --type=sshpop --ssh

# Use Google (OIDC) as the default provisioner in the end user's
# ssh configuration template.
sed -i 's/\%p$/%p --provisioner="Google"/g' /etc/step-ca/templates/ssh/config.tpl

service step-ca start

echo "export STEPPATH=$STEPPATH" >> /root/.profile
