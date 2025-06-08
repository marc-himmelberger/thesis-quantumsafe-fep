#!/bin/bash

set -e

# If TOR_PT_SERVER_TRANSPORT_OPTIONS is not set, use defaults and emit warning
if [[ -z "${TOR_PT_SERVER_TRANSPORT_OPTIONS}" ]]; then
    echo "WARN: Using default value for KEM/OKEM configuration. You should set TOR_PT_SERVER_TRANSPORT_OPTIONS!"
    sleep 1
    export TOR_PT_SERVER_TRANSPORT_OPTIONS="drivel:kem-name=ML-KEM-512;drivel:okem-name=FEO-HQC-128"
fi

for out_folder in tcpdump tcpdump-bridge logs .drivel; do
    rm -rf "$out_folder"
    mkdir -p "$out_folder"
    chmod 777 "$out_folder"
done

docker compose --profile "*" down
docker compose --profile "*" build
docker compose --profile nodebug up --force-recreate --abort-on-container-exit

for service in $(docker compose ps -a --services); do
    docker compose logs --no-log-prefix --no-color $service > logs/$service.log
done