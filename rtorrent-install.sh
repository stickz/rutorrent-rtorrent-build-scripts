#!/bin/bash
# The system user rtorrent is going to run as
RTORRENT_USER=""

# The user that is going to log into rutorrent (htaccess)
WEB_USER=""

# Array with webusers including their hashed paswords
WEB_USER_ARRAY=()

# Temporary download folder for plugins
TEMP_PLUGIN_DIR="rutorrentPlugins/"

# Array of downloaded plugins
PLUGIN_ARRAY=()

#rTorrent users home dir.
HOMEDIR=""

# Formatting variables
#colors
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
GREEN=$(tput setaf 2)
LBLUE=$(tput setaf 6)
RED=$(tput setaf 1)
PURPLE=$(tput setaf 5)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

function CHECKLASTRC {
  if [ $(echo $?) -ne 0 ]; then
   echo "${WHITE}[${RED}FAIL${WHITE}]${NORMAL}"
   exit 1
  else
   echo "${WHITE}[${GREEN}ok${WHITE}]${NORMAL}"
   if [[ "$FASTMODE" -ne "1" ]]; then sleep 5; fi
  fi
}
# Function to check if running user is root
CHECK_ROOT() {
    if [ "$(id -u)" != "0" ]; then
        echo
        echo "${RED}This script must be run as root." 1>&2
        echo
        exit 1
    fi
}

APACHE_UTILS() {
	AP_UT_CHECK="$(dpkg-query -W -f='${Status}' apache2-utils 2>/dev/null | grep -c "ok installed")"
	UNZIP_CHECK="$(dpkg-query -W -f='${Status}' unzip 2>/dev/null | grep -c "ok installed")"
	CURL_CHECK="$(dpkg-query -W -f='${Status}' curl 2>/dev/null | grep -c "ok installed")"

	if [ "$AP_UT_CHECK" -ne 1 ] || [ "$UNZIP_CHECK" -ne 1 ] || [ "CURL_CHECK" -ne 1 ]; then
		echo " One or more of the packages apache2-utils, unzip or curl is not installed and is needed for the setup."
		read -p " Do you want to install it? [y/n] " -n 1
		if [[ $REPLY =~ [Yy]$ ]]; then
			clear
			apt-get update
			apt-get -y install apache2-utils unzip curl wget
		else
			clear
			exit
		fi
	fi
}
# Function to set the system user, rtorrent is going to run as
SET_RTORRENT_USER() {
    con=0
    while [ $con -eq 0 ]; do
        echo -n "Please type a valid system user: "
        read RTORRENT_USER
        if [[ -z $(cat /etc/passwd | grep "^$RTORRENT_USER:") ]]; then
            echo
            echo "This user does not exist!"
        elif [[ $(cat /etc/passwd | grep "^$RTORRENT_USER:" | cut -d: -f3) -lt 0 ]]; then
            echo
            echo "That user's UID is too low!"
        elif [[ $RTORRENT_USER == nobody ]]; then
            echo
            echo "You cant use 'nobody' as user!"
        else
            HOMEDIR=$(cat /etc/passwd | grep /"$RTORRENT_USER":/ | cut -d: -f6)
            con=1
        fi
    done
}
# Function to set the group for Downloads folder and rtorrent config file
SET_RTORRENT_GROUP() {
		RTORRENT_GROUP=$(id -g $RTORRENT_USER)
}

# Function to  create users for the webinterface
SET_WEB_USER() {
	while true; do
		echo -n "Please type the username for the webinterface, system user not required: "
		read WEB_USER
		USER=$(htpasswd -n $WEB_USER 2>/dev/null)
		if [ $? = 0 ]; then
			WEB_USER_ARRAY+=($USER)
			break
		else
			echo
			echo "${RED}Something went wrong!"
			echo "You have entered an unusable username and/or different passwords.${NORMAL}"
			echo
		fi
	done
}

# Function to  change rtorrent port
SET_RT_PORT() {
		echo -n "Please specify port range for rTorrent connections [eg 51000-51500]: "
		read RT_PORT
		echo "Changing port in rtorrent.rc config file"
		sed -i "s/port_range.*/port_range = $RT_PORT/" Files/rtorrent.rc
		CHECKLASTRC
	}
	
# Function to  change apache http port
SET_HTTP_PORT() {
		echo -n "Please specify port for Apache HTTP rutorrent connections [eg 8080]: "
		read HTTP_PORT
		echo "Changing port in 001-default-rutorrent.conf config file"
		sed -i  "s/<VirtualHost \*:.*/<VirtualHost *:$HTTP_PORT>/" Files/001-default-rutorrent.conf 
		CHECKLASTRC
		echo "Changing port in ports.conf config file"
		sed -i  "0,/Listen/ s/Listen.*/Listen $HTTP_PORT/" Files/ports.conf 
		CHECKLASTRC
	}
	
# Function to list WebUI users in the menu
LIST_WEB_USERS() {
	for i in ${WEB_USER_ARRAY[@]}; do
		USER_CUT=$(echo $i | cut -d \: -f 1)
		echo -n " $USER_CUT"
	done
}

# Function to list plugins, downloaded, in the menu
LIST_PLUGINS() {
	if [ ${#PLUGIN_ARRAY[@]} -eq 0 ]; then
		echo "   No plugins downloaded!"
	else
		for i in "${PLUGIN_ARRAY[@]}"; do
			echo "   - $i"
		done
	fi
}


# Function for the Plugins download part.
DOWNLOAD_PLUGIN() {
		curl -L "https://bercik.platinum.edu.pl/repo/plugins-3.6.tar.gz" -o plugins-3.6.tar.gz
		tar -zxvf plugins-3.6.tar.gz -C /tmp/
		if [ $? -eq "0" ]; then
			rm "$file"
			echo
			PLUGIN_ARRAY+=("${name}")
			error="${GREEN}${BOLD}plugins${NORMAL}${GREEN} downloaded, unpacked and moved to temporary plugins folder${NORMAL}"
			return 0
		else
			echo
			error="${RED}Something went wrong.. Error!${NORMAL}"
			return 1
		fi
}


APT_DEPENDENCIES() {
echo "${CYAN}Installing dependencies${NORMAL}"
	apt-get update
	apt-get -y install openssl git apache2 apache2-utils libapache2-mod-scgi unrar-free \
	php php-curl php-cli libapache2-mod-php tmux unzip curl mediainfo
	CHECKLASTRC
}

APT_DEPENDENCIES_NOSCGI() {
echo "${CYAN}Installing dependencies${NORMAL}"
	apt-get update
	apt-get -y install openssl git apache2 apache2-utils unrar-free php-mbstring php-dom python3 sox ffmpeg pip \
	php php-curl php-cli libapache2-mod-php tmux unzip curl mediainfo
    sudo pip3 install cloudscraper --break-system-packages
	CHECKLASTRC
}

# Function for setting up  rtorrent structure
INSTALL_RTORRENT_APT_R98() {

	ldconfig

	# Creating session directory
	echo "${CYAN}Creating session directory ${NORMAL}" 	
	if [ ! -d "$HOMEDIR"/.rtorrent-session ]; then
		mkdir "$HOMEDIR"/.rtorrent-session
		chown "$RTORRENT_USER":"$RTORRENT_GROUP" "$HOMEDIR"/.rtorrent-session
		CHECKLASTRC
	else
		chown "$RTORRENT_USER":"$RTORRENT_GROUP" "$HOMEDIR"/.rtorrent-session
		CHECKLASTRC
	fi
	
	# Creating downloads folder
	echo "${CYAN}Creating Downloads directory ${NORMAL}" 
	if [ ! -d "$HOMEDIR"/Downloads ]; then
		mkdir "$HOMEDIR"/Downloads
		chown "$RTORRENT_USER":"$RTORRENT_GROUP" "$HOMEDIR"/Downloads
		CHECKLASTRC
	else
		chown "$RTORRENT_USER":"$RTORRENT_GROUP" "$HOMEDIR"/Downloads
		CHECKLASTRC
	fi

	# Copying rtorrent.rc file.
	echo "${CYAN}Copying rtorrent.rc${NORMAL}"
	cp Files/rtorrent.rc $HOMEDIR/.rtorrent.rc
	CHECKLASTRC
	chown "$RTORRENT_USER"."$RTORRENT_GROUP" $HOMEDIR/.rtorrent.rc
	#sed -i "s/HOMEDIRHERE/$HOMEDIR/g" $HOMEDIR/.rtorrent.rc ###temp disabled, problems with sed.
}

#Manual SCGI installation because some evil people removed it from main repository
INSTALL_SCGI() {

	echo "${CYAN}Download scgi${NORMAL}"
	wget http://mirrors.kernel.org/ubuntu/pool/universe/s/scgi/libapache2-mod-scgi_1.13-1.1build1_amd64.deb
	echo "${CYAN}Install scgi${NORMAL}"
	dpkg -i libapache2*.deb
	CHECKLASTRC
}	

# Function for installing rutorrent and plugins
INSTALL_RUTORRENT() {
	# Installing rutorrent.
	echo "${CYAN}Installing rutorrent${NORMAL}"
	echo "${YELLOW}Downloading package${NORMAL}"
	git clone https://github.com/Novik/ruTorrent.git
	CHECKLASTRC
    mv ruTorrent rutorrent
	echo "${YELLOW}Renaming${NORMAL}"
	
	if [ -d /var/www/rutorrent ]; then
		rm -r /var/www/rutorrent
	fi

	# Changeing SCGI mount point in rutorrent config.
	echo "${YELLOW}Changing SCGI mount point${NORMAL}"
	sed -i "s/\/RPC2/\/rutorrent\/RPC2/g" ./rutorrent/conf/config.php
	CHECKLASTRC
	echo "${YELLOW}Moving to /var/www/ ${NORMAL}"
	mv -f rutorrent /var/www/
	CHECKLASTRC
	echo "${YELLOW}Cleanup${NORMAL}"
    
	if [ -d "$TEMP_PLUGIN_DIR" ]; then
		mv -fv "$TEMP_PLUGIN_DIR"/* /var/www/rutorrent/plugins
	fi

	# Changing permissions for rutorrent and plugins.
	echo "${CYAN}Changing permissions for rutorrent${NORMAL}"
	chown -R www-data:www-data /var/www/rutorrent
	chmod -R 775 /var/www/rutorrent
	CHECKLASTRC
}

# Function for configuring apache
CONFIGURE_APACHE() {

	# Creating self-signed certs
	if [ ! -f /etc/ssl/certs/apache-selfsigned.crt ]; then
        	openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/apache-selfsigned.key << SSLCONFIG > /etc/ssl/certs/apache-selfsigned.crt
.
.
.
.
Bercik rt-auto-install seedbox
.
.
SSLCONFIG
		a2enmod ssl
        fi

	# Creating symlink for scgi.load
	if [ ! -h /etc/apache2/mods-enabled/scgi.load ]; then
		ln -s /etc/apache2/mods-available/scgi.load /etc/apache2/mods-enabled/scgi.load
	fi

	# Check if apache2 has port 80 enabled
	if ! grep --quiet "^Listen 80$" /etc/apache2/ports.conf; then
		echo "Listen 80" >> /etc/apache2/ports.conf;
	fi

	# Adding ServerName localhost to apache2.conf
	if ! grep --quiet "^ServerName$" /etc/apache2/apache2.conf; then
		echo "ServerName localhost" >> /etc/apache2/apache2.conf;
	fi

	# Creating Apache virtual host
	echo "${CYAN}Creating apache vhost${NORMAL}"
	if [ ! -f /etc/apache2/sites-available/001-default-rutorrent.conf ]; then

		cp Files/001-default-rutorrent.conf /etc/apache2/sites-available/001-default-rutorrent.conf
		cp Files/ports.conf /etc/apache2/ports.conf
		a2ensite 001-default-rutorrent.conf
		CHECKLASTRC
		a2dissite 000-default.conf
		systemctl restart apache2.service
	fi

	# Creating .htaccess file
	printf "%s\n" "${WEB_USER_ARRAY[@]}" > /var/www/rutorrent/.htpasswd
}

INSTALL_FFMPEG() {
	printf "\n# ffpmeg mirror\ndeb http://www.deb-multimedia.org buster main non-free\n" >> /etc/apt/sources.list
	wget http://www.deb-multimedia.org/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_2016.8.1_all.deb
	dpkg -i deb-multimedia-keyring_2016.8.1_all.deb
	apt-get update
	apt-get -y --force-yes install deb-multimedia-keyring
	apt-get update
	apt-get -y install ffmpeg
}

# Function for showing the end result when install is complete
INSTALL_COMPLETE() {
	rm -rf $TEMP_PLUGIN_DIR
	echo "${GREEN}Installation is complete.${NORMAL}"
	echo
	echo
	echo "${RED}Your default Apache2 vhost file has been disabled and replaced with a new one.${NORMAL}"
	echo "${RED}If you were using it, combine the default and rutorrent vhost file and enable it again.${NORMAL}"
	echo
	echo "${PURPLE}Your downloads folder is in ${LBLUE}$HOMEDIR/Downloads${NORMAL}"
	echo "${PURPLE}Sessions data is ${LBLUE}$HOMEDIR/.rtorrent-session${NORMAL}"
	echo "${PURPLE}rtorrent's configuration file is ${LBLUE}$HOMEDIR/.rtorrent.rc${NORMAL}"
	echo
	echo "${PURPLE}If you want to change settings for rtorrent, such as download folder, etc.,"
	echo "you need to edit the '.rtorrent.rc' file. E.g. 'nano $HOMEDIR/.rtorrent.rc'${NORMAL}"
	echo

	# The IPv6 local address, is not very used for now, anyway if needed, just change 'inet' to 'inet6'
	lcl=$(ip addr | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | grep -v "127." | head -n 1)
	ext=$(curl -s http://www.icanhazip.com)
    if [[ "$DEMO" -eq "1" ]]
    then
    ext="DEMO MODE! Public IP hidden"
    fi

	if [[ ! -z "$lcl" ]] && [[ ! -z "$ext" ]]; then
			if [[ $HTTP_PORT != "" ]]; then
		echo "${LBLUE}LOCAL IP:${NORMAL} http://$lcl:$HTTP_PORT/rutorrent"
			else
		echo "${LBLUE}LOCAL IP:${NORMAL} http://$lcl/rutorrent"
			fi
		echo "${LBLUE}EXTERNAL IP:${NORMAL} http://$ext/rutorrent"
		echo
		echo "Visit rutorrent through the above address."
		echo "${RED}Now also available over HTTPS!${NORMAL}"
                echo "Please ${YELLOW} ignore${NORMAL} error messages about _cloudflare spectrogram and screenshots plugin. If you ${YELLOW}desperately${NORMAL} want them, just ${BLUE}apt install  python sox ffmpeg${NORMAL}"
		echo 
	else
		if [[ -z "$lcl" ]]; then
			echo "Can't detect the local IP address"
			echo "Try visit rutorrent at http://127.0.0.1/rutorrent"
			echo 
		elif [[ -z "$ext" ]]; then
			echo "${LBLUE}LOCAL:${NORMAL} http://$lcl/rutorrent"
			echo "Visit rutorrent through your local network"
		else
			echo "Can't detect the IP address"
			echo "Try visit rutorrent at http://127.0.0.1/rutorrent"
			echo 
		fi
	fi
}

INSTALL_SYSTEMD_SERVICE() {
	cat > "/etc/systemd/system/rtorrent.service" <<-EOF
	[Unit]
	Description=rtorrent (in tmux)

	[Service]
	Type=forking
	RemainAfterExit=yes
	User=$RTORRENT_USER
	ExecStart=/usr/bin/tmux -2 new-session -d -s rtorrent rtorrent
	ExecStop=/usr/bin/tmux send-keys -t rtorrent:rtorrent C-q
	RemainAfterExit=no
	Restart=on-failure
	RestartSec=5s
	[Install]
	WantedBy=default.target
	EOF

	systemctl enable rtorrent.service
}

# Function for creating file structure before installation
PREPARE_CONFIG_FILES() {
echo "${CYAN}Creating file structure"
mkdir -p Files

cat > "Files/001-default-rutorrent.conf" << 'EOF'
<VirtualHost *:80>
    #ServerName www.example.com
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

    CustomLog /var/log/apache2/rutorrent.log vhost_combined
    ErrorLog /var/log/apache2/rutorrent_error.log
    SCGIMount /rutorrent/RPC2 127.0.0.1:5000

    <Directory "/var/www/rutorrent">
        AuthName "Tits or GTFO"
        AuthType Basic
        Require valid-user
        AuthUserFile /var/www/rutorrent/.htpasswd
    </Directory>

</VirtualHost>

<IfModule mod_ssl.c>
<VirtualHost *:443>
  #ServerName  www.example.com
  DocumentRoot /var/www/

  LogLevel info ssl:warn
  ErrorLog /var/log/apache2/ssl_error.log
  CustomLog /var/log/apache2/ssl_access.log common
  
  <Directory "/var/www/rutorrent">
      AuthName "Tits or GTFO"
      AuthType Basic
      Require valid-user
      AuthUserFile /var/www/rutorrent/.htpasswd
  </Directory>

SSLEngine on
SSLCertificateFile /etc/ssl/certs/apache-selfsigned.crt
SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key
</VirtualHost>
</IfModule>

# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
EOF

cat > "Files/ports.conf" << 'EOF'
# If you just change the port or add more ports here, you will likely also
# have to change the VirtualHost statement in
# /etc/apache2/sites-enabled/000-default.conf

Listen 80

<IfModule ssl_module>
	Listen 443
</IfModule>

<IfModule mod_gnutls.c>
	Listen 443
</IfModule>

# vim: syntax=apache tss=4 sw=4 sts=4 sr noet
EOF

cat > "Files/rtorrent.rc" << 'EOF'
# This is an example resource file for rTorrent. Copy to
# ~/.rtorrent.rc and enable/modify the options as needed. Remember to
# uncomment the options you wish to enable.

# Maximum and minimum number of peers to connect to per torrent.
#min_peers = 40
#max_peers = 100

# Same as above but for seeding completed torrents (-1 = same as downloading)
#min_peers_seed = 10
#max_peers_seed = 50

# Maximum number of simultanious uploads per torrent.
#max_uploads = 15

# Global upload and download rate in KiB. "0" for unlimited.
#download_rate = 0
#upload_rate = 0

# Default directory to save the downloaded torrents.
directory = ~/Downloads

# Default session directory. Make sure you don't run multiple instance
# of rtorrent using the same session directory. Perhaps using a
# relative path?
session = ~/.rtorrent-session

# Watch a directory for new torrents, and stop those that have been
# deleted.
#schedule = watch_directory,5,5,load_start=./watch/*.torrent
#schedule = untied_directory,5,5,stop_untied=

# Close torrents when diskspace is low.
schedule = low_diskspace,5,60,close_low_diskspace=100M

# The ip address reported to the tracker.
#ip = 127.0.0.1
#ip = rakshasa.no

# The ip address the listening socket and outgoing connections is
# bound to.
#bind = 127.0.0.1
#bind = rakshasa.no

# Port range to use for listening.
port_range = 6790-6999

# Start opening ports at a random position within the port range.
#port_random = no

# Check hash for finished torrents. Might be usefull until the bug is
# fixed that causes lack of diskspace not to be properly reported.
check_hash = no

# Set whetever the client should try to connect to UDP trackers.
#use_udp_trackers = yes

# Alternative calls to bind and ip that should handle dynamic ip's.
#schedule = ip_tick,0,1800,ip=rakshasa
#schedule = bind_tick,0,1800,bind=rakshasa

# Encryption options, set to none (default) or any combination of the following:
# allow_incoming, try_outgoing, require, require_RC4, enable_retry, prefer_plaintext
#
# The example value allows incoming encrypted connections, starts unencrypted
# outgoing connections but retries with encryption if they fail, preferring
# plaintext to RC4 encryption after the encrypted handshake
#
encryption = allow_incoming,enable_retry,try_outgoing

# Enable DHT support for trackerless torrents or when all trackers are down.
# May be set to "disable" (completely disable DHT), "off" (do not start DHT),
# "auto" (start and stop DHT as needed), or "on" (start DHT immediately).
# The default is "off". For DHT to work, a session directory must be defined.
# 
# dht = auto

# UDP port to use for DHT. 
# 
# dht_port = 6881

# Enable peer exchange (for torrents not marked private)
#
# peer_exchange = yes

#
# Do not modify the following parameters unless you know what you're doing.
#

# Hash read-ahead controls how many MB to request the kernel to read
# ahead. If the value is too low the disk may not be fully utilized,
# while if too high the kernel might not be able to keep the read
# pages in memory thus end up trashing.
#hash_read_ahead = 10

# Interval between attempts to check the hash, in milliseconds.
#hash_interval = 100

# Number of attempts to check the hash while using the mincore status,
# before forcing. Overworked systems might need lower values to get a
# decent hash checking rate.
#hash_max_tries = 10

scgi_port = 127.0.0.1:5000


####### Heavy I/O seedbox configuration
####### Uncomment lines below if you have 1Gbit+ Internet link
####### thanks Zebirek
####pieces.memory.max.set = 8048M
####network.max_open_sockets.set = 999
####network.max_open_files.set = 600
####network.http.max_open.set = 99
####network.receive_buffer.size.set =  32M
####network.send_buffer.size.set    = 64M
####pieces.preload.type.set = 2
#####pieces.preload.min_size.set = 262144
#####pieces.preload.min_rate.set = 5120
EOF

}

START_RTORRENT() {
	systemctl start rtorrent.service	
}


# Function to ensure g++ supports C++11
ensure_gpp_cxx11_support() {
    echo "Checking and updating g++ for C++11 support..."
    gpp_version=$(g++ --version | grep "g++")
    if ! g++ --version | grep -q "C++11"; then
        echo "Installing/updating g++ for C++11 support..."
        sudo apt update
        sudo apt install -y g++
    else
        echo "g++ is already configured for C++11 support."
    fi
}

# Function to install required tools and libraries
install_required_tools() {
    echo "Checking and installing required tools and libraries..."
    tools=("make" "svn" "git" "autoconf" "automake" "libtool" "pkg-config" "g++")
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            echo "$tool is not installed. Installing..."
            sudo apt update
            sudo apt install -y $tool
        else
            echo "$tool is already installed."
        fi
    done
    
    # Install ncurses, zlib, libssl, and libcurl development libraries
    if ! dpkg -s libncurses5-dev &> /dev/null; then
        echo "libncurses5-dev is not installed. Installing..."
        sudo apt update
        sudo apt install -y libncurses5-dev
    else
        echo "libncurses5-dev is already installed."
    fi
    
    if ! dpkg -s zlib1g-dev &> /dev/null; then
        echo "zlib1g-dev is not installed. Installing..."
        sudo apt update
        sudo apt install -y zlib1g-dev
    else
        echo "zlib1g-dev is already installed."
    fi
    
    if ! dpkg -s libssl-dev &> /dev/null; then
        echo "libssl-dev is not installed. Installing..."
        sudo apt update
        sudo apt install -y libssl-dev
    else
        echo "libssl-dev is already installed."
    fi
    
    if ! dpkg -s libcurl4-openssl-dev &> /dev/null; then
        echo "libcurl4-openssl-dev is not installed. Installing..."
        sudo apt update
        sudo apt install -y libcurl4-openssl-dev
    else
        echo "libcurl4-openssl-dev is already installed."
    fi
}

# Function to install libudns
install_libudns() {
    # Ensure g++ supports C++11
    ensure_gpp_cxx11_support

    cd $install_dir || exit
    if [ ! -d "libudns" ]; then
        git clone https://github.com/shadowsocks/libudns.git
    fi
    cd libudns || exit
    make clean
    ./autogen.sh
    ./configure --prefix=/usr
    make -j$(nproc) CFLAGS="-O3 -fPIC"
    sudo make -j$(nproc) install
}

# Function to install xmlrpc-c
install_xmlrpc_c() {
    # Ensure g++ supports C++11
    ensure_gpp_cxx11_support

    cd $install_dir || exit
    if ! command -v svn &> /dev/null; then
        echo "SVN command not found. Installing SVN..."
        sudo apt update
        sudo apt install -y subversion
    fi
    if [ ! -d "super_stable" ]; then
        svn checkout svn://svn.code.sf.net/p/xmlrpc-c/code/super_stable super_stable
    fi
    cd super_stable || exit
    make clean
    ./configure --prefix=/usr --disable-cplusplus --disable-wininet-client --disable-libwww-client
    make -j$(nproc) CFLAGS="-O3"
    sudo make install
}

# Function to install libtorrent
install_libtorrent() {
    # Ensure g++ supports C++11
    ensure_gpp_cxx11_support

    cd $install_dir || { echo "Directory $install_dir not found. Exiting..."; exit 1; }
    if [ ! -d "rtorrent" ]; then
        echo "Cloning rtorrent repository..."
        git clone https://github.com/stickz/rtorrent.git || { echo "Failed to clone rtorrent repository. Exiting..."; exit 1; }
        cd rtorrent
        
    else
        echo "rtorrent repository already cloned. Updating..."
        cd rtorrent || { echo "Directory rtorrent not found. Exiting..."; exit 1; }
        git pull origin master || { echo "Failed to pull latest changes from rtorrent repository. Exiting..."; exit 1; }
    fi
    # Print latest 3 tags
    echo "Latest 3 tags:"
    git tag | tail -n 3

    # Prompt user for tag
    read -p "Enter the tag you want to download: " tag
    git pull origin master
    git checkout $tag || { echo "Failed to checkout tag $tag. Exiting..."; exit 1; }

    cd libtorrent || { echo "Directory libtorrent not found. Exiting..."; exit 1; }
    make clean 
    ./autogen.sh || { echo "Failed to run autogen.sh for libtorrent. Exiting..."; exit 1; }
    ./configure --prefix=/usr --enable-aligned --enable-hosted-mode || { echo "Failed to configure libtorrent. Exiting..."; exit 1; }
    make -j$(nproc) CXXFLAGS="-O3" || { echo "Failed to make libtorrent. Exiting..."; exit 1; }
    sudo make install || { echo "Failed to install libtorrent. Exiting..."; exit 1; }
}

# Function to install rtorrent
install_rtorrent() {
    # Ensure g++ supports C++11
    ensure_gpp_cxx11_support

    cd $install_dir || { echo "Directory $install_dir not found. Exiting..."; exit 1; }
    if [ ! -d "rtorrent" ]; then
        echo "Cloning rtorrent repository..."
        git clone https://github.com/stickz/rtorrent.git || { echo "Failed to clone rtorrent repository. Exiting..."; exit 1; }
        cd rtorrent
    else
        echo "rtorrent repository already cloned. Updating..."
        cd rtorrent || { echo "Directory rtorrent not found. Exiting..."; exit 1; }
        git pull origin master || { echo "Failed to pull latest changes from rtorrent repository. Exiting..."; exit 1; }
    fi

    # Print latest 3 tags
    echo "Latest 3 tags:"
    git tag | tail -n 3

    # Prompt user for tag
    read -p "Enter the tag you want to download: " tag
    git checkout $tag || { echo "Failed to checkout tag $tag. Exiting..."; exit 1; }

    cd rtorrent || { echo "Directory rtorrent not found. Exiting..."; exit 1; }
    make clean 
    ./autogen.sh || { echo "Failed to run autogen.sh for rtorrent. Exiting..."; exit 1; }
    ./configure --prefix=/usr --with-xmlrpc-c || { echo "Failed to configure rtorrent. Exiting..."; exit 1; }
    make -j$(nproc) CXXFLAGS="-O3" || { echo "Failed to make rtorrent. Exiting..."; exit 1; }
    sudo make install || { echo "Failed to install rtorrent. Exiting..."; exit 1; }
}





# Prompt for action
echo "What would you like to do?"
echo "1. Install libudns"
echo "2. Install xmlrpc-c"
echo "3. Install libtorrent"
echo "4. Install rtorrent"
echo "5. Full rtorrent installation (libudns, xmlrpc-c, libtorrent, rtorrent)"
echo "6. Update rtorrent installation (libtorrent, rtorrent)"
echo "7. RuTorrent install"
echo "8. RuTorrent full install(libudns, xmlrpc-c, libtorrent, rtorrent, ruTorrent)"
echo "9. exit"

read -p "Enter your choice (1, 2, 3, 4, 5, 6, 7  8 or 9): " choice

# Prompt for installation directory
read -p "Enter the installation directory (default is /home/github): " install_dir
install_dir=${install_dir:-/home/github}

# Create the installation directory if it does not exist
if [ ! -d "$install_dir" ]; then
    echo "Creating installation directory: $install_dir"
    mkdir -p "$install_dir" || { echo "Failed to create directory $install_dir. Exiting..."; exit 1; }
fi

# Install required tools and libraries
install_required_tools

# Perform the chosen action
case $choice in
    1)
        install_libudns
        ;;
    2)
        install_xmlrpc_c
        ;;
    3)
        install_libtorrent
        ;;
    4)
        install_rtorrent
        ;;
    5)
        install_libudns
        install_xmlrpc_c
        install_libtorrent
        install_rtorrent
        ;;
    6)
        install_libtorrent
        install_rtorrent
        ;;
    7)  PREPARE_CONFIG_FILES
        CHECK_ROOT
        APACHE_UTILS
        rm -rf $TEMP_PLUGIN_DIR
        SET_RTORRENT_USER
        SET_RTORRENT_GROUP
        SET_WEB_USER
        SET_RT_PORT
        SET_HTTP_PORT
        APT_DEPENDENCIES_NOSCGI
        INSTALL_RTORRENT_APT_R98
        INSTALL_SCGI
        INSTALL_RUTORRENT
        CONFIGURE_APACHE
        INSTALL_SYSTEMD_SERVICE
		START_RTORRENT
		INSTALL_COMPLETE
        ;;
    8)  
        install_libudns
        install_xmlrpc_c
        install_libtorrent
        install_rtorrent
        PREPARE_CONFIG_FILES
        CHECK_ROOT
        APACHE_UTILS
        rm -rf $TEMP_PLUGIN_DIR
        SET_RTORRENT_USER
        SET_RTORRENT_GROUP
        SET_WEB_USER
        SET_RT_PORT
        SET_HTTP_PORT
        APT_DEPENDENCIES_NOSCGI
        INSTALL_RTORRENT_APT_R98
        INSTALL_SCGI
        INSTALL_RUTORRENT
        CONFIGURE_APACHE
        INSTALL_SYSTEMD_SERVICE
		START_RTORRENT
		INSTALL_COMPLETE
        ;;
    9)  
        echo "Thank you for coming !"
        exit 1
        ;;
    
        
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac
