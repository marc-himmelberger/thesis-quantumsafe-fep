#!/bin/bash

if [ -d liboqs-go ]; then
    echo "liboqs-go found, skipping build."
    exit 0
fi

# TODO differentiate platform based on uname -a (commented out below for Mac)
# WSL: Linux Marc-PC 5.15.167.4-microsoft-standard-WSL2 #1 SMP Tue Nov 5 00:21:55 UTC 2024 x86_64 x86_64 x86_64 GNU/Linux

sudo apt update
sudo apt install -y astyle cmake gcc ninja-build libssl-dev python3-pytest python3-pytest-xdist unzip xsltproc doxygen graphviz python3-yaml valgrind
#brew install cmake ninja openssl@3 wget doxygen graphviz astyle valgrind
#pip3 install pytest pytest-xdist pyyaml

git clone --depth=1 https://github.com/open-quantum-safe/liboqs
cmake -S liboqs -B liboqs/build -DCMAKE_INSTALL_PREFIX="$PWD/liboqs" -DBUILD_SHARED_LIBS=ON
cmake --build liboqs/build --parallel 8
cmake --build liboqs/build --target install

sudo apt install -y cmake pkg-config

lib_path=$PWD/liboqs/lib
include_path=$PWD/liboqs/include

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$lib_path

git clone --depth=1 https://github.com/open-quantum-safe/liboqs-go

# Yes, we also need to put the paths into this file
pc_file=$PWD/liboqs-go/.config/liboqs-go.pc
sed -i "s|/usr/local/include|$include_path|g" "$pc_file"
sed -i "s|/usr/local/lib|$lib_path|g" "$pc_file"

export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$PWD/liboqs-go/.config

cd liboqs-go
go test -v ./oqstests
# TODO: Switch to static compilation as per https://github.com/open-quantum-safe/liboqs-go?tab=readme-ov-file
# -> modify DBUILD_SHARED_LIBS, disable OpenSSL, remove OpenSSL dependency
# TODO: Make sure lyrebird go finds this package after compilation
