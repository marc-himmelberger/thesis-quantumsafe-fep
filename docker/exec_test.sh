#!/bin/bash

rm -rf ./tcpdump

docker compose --profile "*" down
docker compose --profile "*" build
docker compose --profile nodebug up --force-recreate --abort-on-container-exit