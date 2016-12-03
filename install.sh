#!/bin/bash

set -eu

# arguments
ARG_TIMEZONE=$1
ARG_IPADDR=$2
ARG_NETMASK=$3

# default params
ARG_NAMESERVER="8.8.8.8"
ARG_CAPDIR="/cap"

# common functions
print_abort() {
	STR="[ABORT] $1"
	echo $STR
	logger $STR
}

print_title () {
	echo
	echo
	echo "# $1"
	logger "# $1"
}

print_task() {
	echo " >> $1"
	logger " >> $1"
}

print_subtask() {
	echo " >>> $1"
	logger " >>> $1"
}

check_privilege() {
	iam=`whoami`
	if [ ${iam} != "root" ]; then
		print_abort "requires root privilege"
	fi
}

install_package() {
	PKGS=$1
	print_subtask "installing $PKGS"
	apt-get install --force-yes -y $PKGS
}

backup_file() {
	target=$1
	suffix=`date "+%Y%m%d%H%M%S"`
	cp $target ${target}.${suffix}
}

show_params() {
	print_title "Global Params:"
	echo "  - TIMEZONE = $ARG_TIMEZONE"
	echo "  - IPADDR   = $ARG_IPADDR"
	echo "  - NETMASK  = $ARG_NETMASK"
}

do_general_settings() {
	print_title "General Settings"
	
	print_task "setting timezone"
	zone_path=/usr/share/zoneinfo/${ARG_TIMEZONE}
	if [ ! -e ${zone_path} ]; then
		print_abort "zoneinfo for ${ARG_TIMEZONE} does not exist"
	fi
	cp /etc/localtime /etc/localtime.org
	ln -sf /usr/share/zoneinfo/${ARG_TIMEZONE} /etc/localtime
	
	print_task "setting interface address for eth0"
	tmppath=/tmp/if-eth0.conf
	cat << EOS > $tmppath
Source-directory /etc/network/interfaces.d

auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
	address ${ARG_IPADDR}
	netmask ${ARG_NETMASK}
	dns-nameservers ${ARG_NAMESERVER}
EOS
	cp /etc/network/interfaces /etc/network/interfaces.org
	mv $tmppath /etc/network/interfaces
	# don't restart networking service; reboot will handle this

}

disable_unnecessary_services() {
	print_title "Disabling unnecessary services"
	print_task "remove dhcpcd"
	update-rc.d dhcpcd remove
}

install_required_packages() {
	print_title "Installing required packages"
	print_task "packages for soracomair"
	install_package wvdial screen
	print_task "packages for display"
	install_package expect raspberrypi-bootloader adafruit-pitft-helper
	print_task "packages for panopticon TFT"
	install_package midori matchbox x11-xserver-utils
	print_task "gems for panopticon"
	gem install --no-document sinatra
}

setup_pitft() {
	print_title "Setup PiTFT"
	ptn_console="Would you like the console to appear on the PiTFT display"
	ptn_gpio="to act as a on/off button"
	ptn_term="Success!"
	
	expect -c "
set timeout 5
spawn env LANG=C /usr/bin/adafruit-pitft-helper -t 28r
expect \"${ptn_console}\"
send \"y\n\"
expect \"${ptn_gpio}\"
send \"n\n\"
expect \"${ptn_term}\"
exit 0
"

	cat << EOS > /etc/X11/xorg.conf.d/99-calibration.conf
Section "InputClass"
        Identifier              "calibration"
        MatchProduct            "stmpe-ts"
        Option  "Calibration"   "3800 200 200 3800"
        Option  "SwapAxes"      "1"
        Option "EmulateThirdButton"               "1"
        Option "EmulateThirdButtonTimeout"        "750"
        Option "EmulateThirdButtonMoveThreshold" "30"
EndSection
EOS
}

setup_soracomair() {
	print_title "Setup soracomair"
	tmpdir=/tmp/soracomair_wvdial
	git clone https://github.com/enukane/soracom_wvdial.git $tmpdir
	sh $tmpdir/install.sh
}

setup_panopticon() {
	print_title "Setup Panopticon"
	gem install panopticon
	tmpdir=/tmp/panopticon
	git clone https://github.com/enukane/panopticon.git $tmpdir
	sh $tmpdir/extra/install.sh
}

setup_kiosk_mode() {
	print_title "Setup Kiosk Mode"
	tmpdir=/tmp/pitft-kiosk
	git clone https://github.com/enukane/pitft-kiosk-mode $tmpdir
	sh $tmpdir/install.sh http://localhost:8080
}

setup_capdir() {
	print_title "Setup Capture Data Directory"
	mkdir $ARG_CAPDIR
	chmod a+w $ARG_CAPDIR
	ln -s /cap /home/pi/cap
}



# main logic
check_privilege
show_params
do_general_settings
disable_unnecessary_services
install_required_packages

setup_pitft
setup_soracomair
setup_panopticon
setup_kiosk_mode

setup_capdir

print_title "Setup DONE, exiting"
