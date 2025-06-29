#!/usr/bin/env bash

NICK=${NICKNAME:-DockerDrivelBridge}

echo "Using NICKNAME=${NICK}, OR_PORT=${OR_PORT}, PT_PORT=${PT_PORT}, and EMAIL=${EMAIL}."

ADDITIONAL_VARIABLES_PREFIX="TORBRIDGE_"
ADDITIONAL_VARIABLES=

if [[ "$TORBRIDGE_ENABLE_ADDITIONAL_VARIABLES" == "1" ]]
then
    ADDITIONAL_VARIABLES="# Additional properties from processed '$ADDITIONAL_VARIABLES_PREFIX' environment variables"
    echo "Additional properties from '$ADDITIONAL_VARIABLES_PREFIX' environment variables processing enabled"

    IFS=$'\n'
    for V in $(env | grep "^$ADDITIONAL_VARIABLES_PREFIX"); do
        VKEY_ORG="$(echo $V | cut -d '=' -f1)"
        VKEY="${VKEY_ORG#$ADDITIONAL_VARIABLES_PREFIX}"
        VVALUE="$(echo $V | cut -d '=' -f2)"
        echo "Overriding '$VKEY' with value '$VVALUE'"
        ADDITIONAL_VARIABLES="$ADDITIONAL_VARIABLES"$'\n'"$VKEY $VVALUE"
    done
fi

cat > /etc/tor/torrc << EOF
RunAsDaemon 0
# We don't need an open SOCKS port.
SocksPort 0
BridgeRelay 1
Nickname ${NICK}
Log notice file /var/log/tor/log
Log notice stdout
ServerTransportPlugin drivel exec /usr/bin/wrapper.sh
ExtORPort auto
DataDirectory /var/lib/tor

# The variable "OR_PORT" is replaced with the OR port.
ORPort ${OR_PORT}

# The variable "PT_PORT" is replaced with the drivel port.
ServerTransportListenAddr drivel 0.0.0.0:${PT_PORT}

# The variable "EMAIL" is replaced with the operator's email address.
ContactInfo ${EMAIL}

PublishServerDescriptor 0
BridgeDistribution none

$ADDITIONAL_VARIABLES
EOF

echo "Starting tor."
tor -f /etc/tor/torrc
