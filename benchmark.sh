#!/bin/bash

set -e

sed_no_backup="-i"

# MacOS specifics
if [ "Darwin" = "$(uname -s)" ]; then
	sed_no_backup="-i ''"
fi

rm -rf results/
mkdir -p results/benchmarks

ensure_no_padding () {
    orig="pad := make([]byte, padLen)"
    repl="pad := make([]byte, 0)"
	sed $(sed_no_backup) "s|$orig|$repl|g" lyrebird/**/*.go
}
ensure_bridge_obfs4 () {
    sed $(sed_no_backup) "s|drivel|obfs4|g" docker/bridge/start-tor.sh
}
ensure_bridge_drivel () {
    sed $(sed_no_backup) "s|obfs4|drivel|g" docker/bridge/start-tor.sh
}
ensure_drivel_x25519 () {
    sed $(sed_no_backup) -E "s|\skemName\s+=.*| kemName = \"x25519\"|g" lyrebird/transports/drivel/drivel.go
    sed $(sed_no_backup) -E "s|\sokemName\s+=.*| okemName = \"EtE-x25519\"|g" lyrebird/transports/drivel/drivel.go
}

# Removes padding from lyrebird, and starts a full run in Docker
# Reuqires that lyrebird be up-to-date (main branch)
# Results are saved to the results directory
# Usage: full_run obfs4 OR full_run drivel <drivel_config>
full_run () {
    ensure_no_padding
    ensure_bridge_$1
    out_dir="$1"
    if [ "$2" != ""]; then
        out_dir="$1-$2"
        ensure_drivel_$2
    fi
    (cd docker; ./exec_test.sh)
    mkdir -p results/runs/$out_dir
    cp -r docker/logs results/runs/$out_dir
    cp -r docker/tcpdump results/runs/$out_dir
}

cd lyrebird

# assert no changes to lyrebird working tree
if ! git diff-index --quiet HEAD --; then
    echo "Changes found in lyrebird/ working tree. Aborting benchmark."
    git status -s
    exit 1
fi

# 1. Go benchmarks
# 1a. obfs4-bench branch: Original obfs4, total handshake time
git checkout obfs4-bench
make build
echo "=> Starting benchmark"
make bench > ../results/benchmarks/obfs4-bench.txt
# 1b. main branch: Up-to-date obfs4 & drivel, total handshake time
git checkout main
make build
echo "=> Starting benchmark"
make bench > ../results/benchmarks/main.txt

cd ..

# 2. Full-stack comparisons
# 2a. Full run obfs4
full_run obfs4

# 2b. Full run drivel(x25519)
full_run drivel x25519

cd lyrebird
git reset --hard
cd ..

# TODO 2c. Full runs with more KEM/OKEM combinations

# 1. Performance comparison obfs4(old) vs obfs4(new) vs drivel(x25519ell2) - using Benchmark(.*)Handshake
# 2. Full-stack comparison obfs4(new) vs drivel(x25519ell2)
# 3. Full-stack comparison drivel(x25519ell2) vs other combinations