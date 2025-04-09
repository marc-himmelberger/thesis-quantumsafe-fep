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
}
ensure_bridge_drivel () {
    sed $sed_no_backup "s|obfs4|drivel|g" docker/bridge/start-tor.sh docker/bridge/get-bridge-line
}
ensure_drivel_x25519 () {
    sed $sed_no_backup -E "s|\skemName\s+=.*| kemName = \"x25519\"|g" lyrebird/transports/drivel/drivel.go
    sed $sed_no_backup -E "s|\sokemName\s+=.*| okemName = \"EtE-x25519\"|g" lyrebird/transports/drivel/drivel.go
}
ensure_drivel_classicmceliece_348864 () {
    sed $sed_no_backup -E "s|\skemName\s+=.*| kemName = \"Classic-McEliece-348864\"|g" lyrebird/transports/drivel/drivel.go
    sed $sed_no_backup -E "s|\sokemName\s+=.*| okemName = \"EtE-Classic-McEliece-348864\"|g" lyrebird/transports/drivel/drivel.go
}
ensure_drivel_classicmceliece_6688128 () {
    sed $sed_no_backup -E "s|\skemName\s+=.*| kemName = \"Classic-McEliece-6688128\"|g" lyrebird/transports/drivel/drivel.go
    sed $sed_no_backup -E "s|\sokemName\s+=.*| okemName = \"EtE-Classic-McEliece-6688128\"|g" lyrebird/transports/drivel/drivel.go
}
ensure_drivel_classicmceliece_6960119 () {
    sed $sed_no_backup -E "s|\skemName\s+=.*| kemName = \"Classic-McEliece-6960119\"|g" lyrebird/transports/drivel/drivel.go
    sed $sed_no_backup -E "s|\sokemName\s+=.*| okemName = \"EtE-Classic-McEliece-6960119\"|g" lyrebird/transports/drivel/drivel.go
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

    cd lyrebird

    log "###############"
    log "# START BENCH #"
    log "###############"
    
    # 1. Go benchmarks
    # 1a. obfs4-bench branch: Original obfs4, total handshake time
    git checkout obfs4-bench
    make build
    echo "=> Starting benchmark"
    make bench > $1/benchmarks/obfs4-bench.txt

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

    # 2. Full-stack comparisons
    # 2a. Full run obfs4
    full_run $1 obfs4

    # 2b. Full run drivel(x25519)
    full_run $1 drivel x25519

    # 2c. Full runs with more KEM/OKEM combinations
    full_run $1 drivel classicmceliece_348864
    full_run $1 drivel classicmceliece_6688128
    full_run $1 drivel classicmceliece_6960119

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
    (single_complete_bench $out_dir) 2>&1 >$out_dir/benchmark.log
    log "Completed benchmark for $out_dir"
done
log "Completed all benchmarks :D"

# Kick off data structuring and plotting
# 1. Performance comparison obfs4(old) vs obfs4(new) vs drivel(x25519ell2) - using Benchmark(.*)Handshake
# 2. Full-stack comparison obfs4(new) vs drivel(x25519ell2)
# 3. Full-stack comparison drivel(x25519ell2) vs other combinations

log "Structuring data..."
python3 results_structure.py
log "Plotting..."
Rscript results_plot.R
log "Done."
