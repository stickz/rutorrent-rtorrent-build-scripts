#!/bin/bash

# Create build directory
mkdir ~/build

# Build and install libtorrent
cd ~/build
git clone https://github.com/rakshasa/libtorrent
cd ~/build/libtorrent
autoreconf -vfi
./configure --prefix=/usr --enable-aligned
make -j$(nproc) CXXFLAGS="-g"
make install

# Build and install rtorrent
cd ~/build
git clone https://github.com/rakshasa/rtorrent
cd ~/build/rtorrent
autoreconf -vfi
./configure --prefix=/usr --with-xmlrpc-tinyxml2
make -j$(nproc) CXXFLAGS="-g"
make install

# Remove build directory
rm -rf ~/build
