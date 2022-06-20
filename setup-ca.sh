#!/bin/bash

OIDC_CLIENT_ID="[OAuth client ID]" # from Google
OIDC_CLIENT_SECRET="[OAuth client secret]" # from Google
ALLOWED_DOMAIN="[the domain name of accounts your users will use to sign to Google]"
CA_NAME="[A name for your CA]"
ROOT_KEY_PASSWORD="[A password for your CA's root key]"
EMAIL="your@email.address"

OPENID_CONFIG_ENDPOINT="https://accounts.google.com/.well-known/openid-configuration"

# All your CA config and certificates will go into $STEPPATH.
export STEPPATH=/etc/step
mkdir -p $STEPPATH
chmod 700 $STEPPATH
echo $ROOT_KEY_PASSWORD > $STEPPATH/password.txt

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


# The sshpop provisioner lets hosts renew their ssh certificates
step ca provisioner add SSHPOP --type=sshpop --ssh

# Use Google (OIDC) as the default provisioner in the end user's
# ssh configuration template.
sed -i 's/\%p$/%p --provisioner="Google"/g' /etc/step-ca/templates/ssh/config.tpl

service step-ca start

echo "export STEPPATH=$STEPPATH" >> /root/.profile
