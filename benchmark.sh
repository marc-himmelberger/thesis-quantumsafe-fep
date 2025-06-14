#!/bin/bash

set -e

log () {
    echo $(date -u "+%Y/%m/%d %H:%M:%S") $1
}

sed_no_backup="-i"

# MacOS specifics
if [ "Darwin" = "$(uname -s)" ]; then
	sed_no_backup="-i ''"
fi

# Iteration count
no_complete_replicas=8
if [[ -n "$1" ]]; then
    no_complete_replicas=$1
fi
echo "Performing $no_complete_replicas replicas"

ensure_no_padding () {
    orig="MaxPadLength)"
    repl="MinPadLength)"
	sed $sed_no_backup "s|$orig|$repl|g" /home/marc/thesis-quantumsafe-fep/lyrebird/transports/drivel/handshake.go
    sed $sed_no_backup "s|$orig|$repl|g" /home/marc/thesis-quantumsafe-fep/lyrebird/transports/obfs4/handshake_ntor.go
}
ensure_padding () {
    orig="MinPadLength)"
    repl="MaxPadLength)"
	sed $sed_no_backup "s|$orig|$repl|g" /home/marc/thesis-quantumsafe-fep/lyrebird/transports/drivel/handshake.go
    sed $sed_no_backup "s|$orig|$repl|g" /home/marc/thesis-quantumsafe-fep/lyrebird/transports/obfs4/handshake_ntor.go
}
ensure_bridge_obfs4 () {
    sed $sed_no_backup "s|drivel|obfs4|g" docker/bridge/start-tor.sh docker/bridge/get-bridge-line
    sed $sed_no_backup "s|node-id=|cert=|g" docker/bridge/start-tor.sh docker/bridge/get-bridge-line
}
ensure_bridge_drivel () {
    sed $sed_no_backup "s|obfs4|drivel|g" docker/bridge/start-tor.sh docker/bridge/get-bridge-line
    sed $sed_no_backup "s|cert=|node-id=|g" docker/bridge/start-tor.sh docker/bridge/get-bridge-line
}
config_schemes () {
    # Uses scheme names as arguments (KEM, then OKEM) to set enviroment variable accordingly
    # Example: config_schemes "x25519" "FEO-x25519"
    export TOR_PT_SERVER_TRANSPORT_OPTIONS="drivel:kem-name=$1;drivel:okem-name=$2"
}
# TODO change these to actually use our 12 parameter sets
ensure_drivel_L0 () {
    config_schemes "x25519" "FEO-x25519"
}
ensure_drivel_L1a () {
    config_schemes "ML-KEM-512" "FEO-ML-KEM-512"
}
ensure_drivel_L1b () {
    config_schemes "BIKE-L1" "FEO-ML-KEM-512"
}
ensure_drivel_L1c () {
    config_schemes "ML-KEM-512" "FEO-HQC-128"
}
ensure_drivel_L1d () {
    config_schemes  "ML-KEM-512" "FEO-Classic-McEliece-348864"
}
ensure_drivel_L3a () {
    config_schemes "ML-KEM-768" "FEO-ML-KEM-768"
}
ensure_drivel_L3b () {
    config_schemes "BIKE-L3" "FEO-ML-KEM-768"
}
ensure_drivel_L3c () {
    config_schemes "ML-KEM-768" "FEO-HQC-192"
}
ensure_drivel_L3d () {
    config_schemes  "ML-KEM-768" "FEO-Classic-McEliece-460896"
}
ensure_drivel_L5a () {
    config_schemes "ML-KEM-1024" "FEO-ML-KEM-1024"
}
ensure_drivel_L5b () {
    config_schemes "BIKE-L5" "FEO-ML-KEM-1024"
}
ensure_drivel_L5c () {
    config_schemes "ML-KEM-1024" "FEO-HQC-256"
}
ensure_drivel_L5d () {
    config_schemes  "ML-KEM-1024" "FEO-Classic-McEliece-6688128"
}

# Removes padding from lyrebird, and starts a full run in Docker
# Reuqires that lyrebird be up-to-date (main branch)
# Results are saved to the given out_folder directory
# Usage: full_run out_folder obfs4 OR full_run out_folder drivel <drivel_config>
full_run () {
    echo "### FULL RUN: $2, $3 ###"
    ensure_no_padding
    ensure_bridge_$2
    out_dir="$2"
    if [ "$3" != "" ]; then
        out_dir="$2-$3"
        ensure_drivel_$3
    fi
    (cd docker; ./exec_test.sh)
    mkdir -p $1/runs/$out_dir
    cp -r docker/logs $1/runs/$out_dir
    cp -r docker/tcpdump $1/runs/$out_dir
}

single_complete_bench () {
    cd lyrebird

    # assert no changes to lyrebird working tree
    if ! git diff-index --quiet HEAD --; then
        echo "Changes found in lyrebird/ working tree. Aborting benchmark."
        git status -s
        exit 1
    fi

    cd ..

    echo "Found clean lyrebird/ working tree. Proceeding..."
    mkdir -p $1/benchmarks

    if (( $2 > 8 )); then
        cd lyrebird

        log "###############"
        log "#  BENCH 1/2  #"
        log "###############"
        
        # 1. Go benchmarks
        # 1a. obfs4-bench branch: Original obfs4, total handshake time
        git checkout obfs4-bench
        make build
        echo "=> Starting benchmark"
        make bench > $1/benchmarks/obfs4-bench.txt

        log "###############"
        log "#  BENCH 2/2  #"
        log "###############"

        # 1b. main branch: Up-to-date obfs4 & drivel, total handshake time
        git checkout main
        make build
        echo "=> Starting benchmark"
        make bench > $1/benchmarks/main.txt

        log "###############"
        log "#  END BENCH  #"
        log "# START RUNS  #"
        log "###############"

        cd ..
    fi

    # 2. Full-stack comparisons
    # 2a. Full run obfs4
    full_run $1 obfs4

    # 2b. Full run drivel(x25519)
    full_run $1 drivel L0

    # 2c. Full runs with more KEM/OKEM combinations    
    full_run $1 drivel L1a
    full_run $1 drivel L1b
    full_run $1 drivel L1c
    full_run $1 drivel L1d
    full_run $1 drivel L3a
    full_run $1 drivel L3b
    full_run $1 drivel L3c
    full_run $1 drivel L3d
    full_run $1 drivel L5a
    full_run $1 drivel L5b
    full_run $1 drivel L5c
    full_run $1 drivel L5d

    log "###############"
    log "#  END RUNS   #"
    log "###############"

    cd lyrebird
    git reset --hard
    cd ..
}

rm -rf results/
mkdir -p results/
for i in $(seq 1 $no_complete_replicas); do
    out_dir=results/bench-$(printf "%02d" $i)
    out_dir=$(realpath $out_dir)
    mkdir -p $out_dir

    log "Starting benchmark into $out_dir"
    (single_complete_bench $out_dir $i) 2>&1 >$out_dir/benchmark.log
    log "Completed benchmark for $out_dir"
done
log "Completed all benchmarks :D"

# Kick off data structuring and plotting
log "Structuring data..."
python3 results_structure.py
log "Plotting..."
Rscript results_plot.R
log "Done."
