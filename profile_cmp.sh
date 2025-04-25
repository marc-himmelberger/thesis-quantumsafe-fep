#!/bin/bash

# Quick and dirty script to compare CPU and Memory profiles between an obfs4 handshake and a Drivel handshake
mkdir -p results
out_folder=$(realpath results/profiles)
cd lyrebird

# Make sure the same size of buffer is used
# TODO remove once we have fragmentation
maxHandshake_pattern="maxHandshakeLength =.*$"
handshake_file="transports/drivel/handshake.go"
old_line=$(cat "$handshake_file" | grep -o "$maxHandshake_pattern")
sed -i "s/$maxHandshake_pattern/maxHandshakeLength = 8192/g" "$handshake_file"
echo "Old entry: '$old_line' changed to 8192"

# Profile for 30s each
rm -rf $out_folder
mkdir -p $out_folder
obfs4_pattern="^BenchmarkObfs4Handshake$"
drivel_pattern="^BenchmarkDrivelHandshake/x25519\|FEO-x25519$"
benchtime="1000x"
count="10"

echo "Profiling: obfs4 for $count times $benchtime"
go test -benchmem -run=^$ -bench $obfs4_pattern -count=$count -benchtime=$benchtime ./transports/obfs4 \
    -cpuprofile $out_folder/obfs4.cpu.prof -memprofile $out_folder/obfs4.mem.prof -o $out_folder/obfs4.test
echo "Profiling: drivel for $benchtime"
go test -benchmem -run=^$ -bench $drivel_pattern -count=$count -benchtime=$benchtime ./transports/drivel \
    -cpuprofile $out_folder/drivel.cpu.prof -memprofile $out_folder/drivel.mem.prof -o $out_folder/drivel.test

# undo the buffer size change
sed -i "s/$maxHandshake_pattern/$old_line/g" "$handshake_file"
echo "Old entry: maxHandshakeLength changed back to '$old_line'"

echo "Comparing profiles:"
go tool pprof -http=":" -no_browser -diff_base $out_folder/obfs4.cpu.prof $out_folder/drivel.cpu.prof &
pprof_pid1=$!
go tool pprof -http=":" -no_browser -diff_base $out_folder/obfs4.mem.prof $out_folder/drivel.mem.prof &
pprof_pid2=$!
sleep 2
read -p "Press key to continue... " -n1 -s
echo "Killing background processes"
kill -9 $pprof_pid1 $pprof_pid2
