#!/bin/bash

# Create build directory
mkdir ~/build

# Build and install libudns
cd ~/build && git clone https://github.com/shadowsocks/libudns
cd libudns
./autogen.sh
./configure --prefix=/usr
make -j$(nproc) CFLAGS="-O3 -fPIC"
make -j$(nproc) install

# Build and install xmlrpc-c
cd ~/build && svn checkout svn://svn.code.sf.net/p/xmlrpc-c/code/super_stable
cd super_stable
./configure --prefix=/usr --disable-cplusplus --disable-wininet-client --disable-libwww-client
make -j$(nproc) CFLAGS="-O3"
make install

# Clone libtorrent & rtorrent stickz repo
cd ~/build && git clone https://github.com/stickz/rtorrent/

# Build and install libtorrent
cd ~/build/rtorrent/libtorrent
./autogen.sh
./configure --prefix=/usr --enable-aligned
make -j$(nproc) CXXFLAGS="-O3 -march=native -flto=\"$(nproc)\" -Werror=odr -Werror=lto-type-mismatch -Werror=strict-aliasing"
make install

# Build and install rtorrent
cd ~/build/rtorrent/rtorrent
./autogen.sh
./configure --prefix=/usr --with-xmlrpc-c
make -j$(nproc) CXXFLAGS="-O3 -march=native -flto=\"$(nproc)\" -Werror=odr -Werror=lto-type-mismatch -Werror=strict-aliasing"
make install

# Remove build directory
rm -rf ~/build
