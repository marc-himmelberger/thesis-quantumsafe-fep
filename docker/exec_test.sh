#!/bin/bash

set -e

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