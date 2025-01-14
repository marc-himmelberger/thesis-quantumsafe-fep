#!/bin/sh

echo "############"
echo "# /test.sh #"
echo "############"


# Start tor
/etc/init.d/tor start 2>&1 > test_initd.log
if [ "$?" = "0" ]; then
    echo "[PASS] Tor service started"
else
    echo "[FAIL] Tor service failed to start"
fi

# Check that tor circuit is established
# The log files containing info about $1 should contain $2, otherwise something went wrong
tor_getinfo () {
    nc_out=$(nc -N 127.0.0.1 12345 <<EOF
AUTHENTICATE
GETINFO $1
EOF
    )
    echo "$nc_out" > "test_$1.log"
    grep "$2" "test_$1.log" > /dev/null
    if [ "$?" = "0" ]; then
        echo "[PASS] Tor info about $1 looks good"
    else
        echo "[FAIL] Tor info about $1 does not contain '$2':"
        echo "$nc_out" | awk '{print "  " $0}'
    fi
}

sleep 5
tor_getinfo "circuit-status" " BUILT "
tor_getinfo "orconn-status" " CONNECTED"
tor_getinfo "entry-guards" " up"

# Check IP with and without Tor
regular_json=$(curl -sS -k https://4.myip.is)
regular_ip=$(echo $regular_json | jq -r '.ip')
torify_json=$(torify curl -sS -k https://4.myip.is)
torify_ip=$(echo $torify_json | jq -r '.ip')

if [ "$regular_ip" != "$torify_ip" ]; then
    echo "[PASS] Received a new IP"
    echo "  Regular IP: $regular_json"
    echo "  Torify IP:  $torify_json"
else
    echo "[FAIL] IP did not change"
    echo "  Regular IP: $regular_json"
    echo "  Torify IP:  $torify_json"
fi