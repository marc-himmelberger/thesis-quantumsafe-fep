#!/bin/bash

set -e

mkdir -p tcpdump logs
rm -f tcpdump/*
rm -f logs/*

docker compose --profile "*" down
docker compose --profile "*" build
docker compose --profile nodebug up --force-recreate --abort-on-container-exit

for service in $(docker compose ps -a --services); do
    docker compose logs --no-log-prefix --no-color $service > logs/$service.log
done