#!/bin/bash

log () {
    echo $(date -u "+%Y/%m/%d %H:%M:%S") $1
}

log "############"
log "# /test.sh #"
log "############"

# Check tor with version
tor --version
if [ "$?" = "0" ]; then
    log "[PASS] Tor present"
else
    log "[FAIL] Tor executable not present"
fi

# Read Bridge Line, only add to torrc if not already present (otherwise prevents restarts)
if ! grep -q "iat-mode" /etc/tor/torrc; then
    cat /.bridgeinfo >> /etc/tor/torrc
fi

# Set control password
torpass=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 32)
torhash=$(su tor-client -c "tor --hash-password \"$torpass\" 2>/dev/null")
echo "HashedControlPassword $torhash" >> /etc/tor/torrc

log "Current torrc:"
cat /etc/tor/torrc

# Start tor
/etc/init.d/tor start 2>&1 > test_initd.log
if [ "$?" = "0" ]; then
    log "[PASS] Tor service started"
else
    log "[FAIL] Tor service failed to start"
fi

# Check that tor circuit is established
# The log files containing info about $1 should contain $2, otherwise something went wrong
tor_getinfo () {
    nc_out=$(nc -N 127.0.0.1 9051 <<EOF
AUTHENTICATE "$torpass"
GETINFO $1
EOF
    )
    echo "$nc_out" > "test_$1.log"
    grep "$2" "test_$1.log" > /dev/null
    if [ "$?" = "0" ]; then
        log "[PASS] Tor info about $1 looks good"
    else
        log "[FAIL] Tor info about $1 does not contain '$2':"
        log "$nc_out" | awk '{print "  " $0}'
    fi
}

log "Waiting 15s"
sleep 15
log "Continuing..."
tor_getinfo "circuit-status" " BUILT "
tor_getinfo "orconn-status" " CONNECTED"
tor_getinfo "entry-guards" " up"

# Check IP with and without Tor
# 'https://api.ipify.org?format=json'
IPCHECKER_DOMAIN="api.ipify.org"
IPCHECKER_IP=$(dig +answer $IPCHECKER_DOMAIN +short | head -n1)
log "  using $IPCHECKER_DOMAIN at $IPCHECKER_IP"
# -s (silent) -S (show errors) -k (insecure)
regular_json=$(curl -sS -k "https://$IPCHECKER_DOMAIN?format=json" --resolve $IPCHECKER_DOMAIN:443:$IPCHECKER_IP)
    log "  Regular IP: $regular_json"
regular_ip=$(echo $regular_json | jq -r '.ip')
torify_json=$(torify curl -sS -k "https://$IPCHECKER_DOMAIN?format=json" --resolve $IPCHECKER_DOMAIN:443:$IPCHECKER_IP)
    log "  Torify IP:  $torify_json"
torify_ip=$(echo $torify_json | jq -r '.ip')

if [ "$regular_ip" != "$torify_ip" ]; then
    log "[PASS] Received a new IP"
else
    log "[FAIL] IP did not change"
fi

# give time for tcpdump to ensure no packet loss
sleep 5

# TODO check on bridge logs or different websites, to see what did or didn't work
# TODO also check during/after connection
# TODO check without pluggable transport
# TODO check with obfs4
# TODO investigate DNS again?