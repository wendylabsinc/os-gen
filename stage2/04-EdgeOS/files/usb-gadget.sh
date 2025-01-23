#!/bin/bash

# Function to generate a MAC address from a string
# uses "Locally Administered Addresses"
# This means the second character of the first octet should be 2, 6, A, or E (in hexadecimal).
generate_mac() {
    local input="$1"
    # Generate a SHA-256 hash of the input
    local hash=$(echo -n "$input" | shasum -a 256 | awk '{print $1}')
    
    # Take the first 12 characters of the hash
    local mac_base=${hash:0:12}
    
    # Ensure the address is locally administered by setting the second character to 2, 6, A, or E
    local first_byte=${mac_base:0:2}
    local second_char=$(printf '%x' $((0x$first_byte & 0xfe | 0x02)))
    
    # Construct the MAC address
    printf "%02x:%02x:%02x:%02x:%02x:%02x" \
       0x$second_char \
       0x${mac_base:2:2} \
       0x${mac_base:4:2} \
       0x${mac_base:6:2} \
       0x${mac_base:8:2} \
       0x${mac_base:10:2}
}

### place this in /usr/local/sbin/usb-gadget.sh to run at boot

# Variables that should be input for every new device
GADGET_NAME="edgeos_pi5"
MANUFACTURER="EdgeOS"
PRODUCT="EdgeOS Device"

# Get Pi serial; to be used to generate MAC addresses
PI_SERIAL=$(cat /proc/cpuinfo | grep "Serial" | awk -F: '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }')

# Define gadget dir
GADGET_DIR="/sys/kernel/config/usb_gadget/$(echo $GADGET_NAME)"
mkdir -p $GADGET_DIR
cd $GADGET_DIR

# Set vendor and product
echo 0x1d6b > idVendor # Linux Foundation
echo 0x0104 > idProduct # Multifunction Composite Gadget

echo 0x0103 > bcdDevice # v1.0.3
echo 0x0320 > bcdUSB # USB2
echo 2 > bDeviceClass

# Set English strings
mkdir -p strings/0x409
echo $PI_SERIAL > strings/0x409/serialnumber
echo $MANUFACTURER > strings/0x409/manufacturer
echo $PRODUCT > strings/0x409/product

# Create configuration
mkdir -p configs/c.1/strings/0x409

# This string is what the USB host sees when it enumerates the device's configurations 
# (for example, in tools like lsusb or Windows Device Manager). Labeling it "CDC" indicates that this particular configuration implements some form of USB Communications Device Class interface (e.g., CDC-ECM for USB Ethernet, CDC-ACM for virtual serial ports, etc.).
echo "CDC" > configs/c.1/strings/0x409/configuration

# 2x450mA = 900mA = power for usb3.x
# 2x250mA = 500mA = power for usb2.x
echo 250 > configs/c.1/MaxPower

# The configs/c.1/bmAttributes file in your USB gadget's configuration directory corresponds to the 
# bmAttributes field in the USB configuration descriptor. This field specifies important power 
# and feature characteristics of your USB device configuration, such as whether the device is 
# bus-powered or self-powered, and whether it supports remote wakeup.
#
# 0xA0 (160 in decimal):
# 	•	Bit 7 = 1 (always set)
# 	•	Bit 6 = 0 (bus-powered)
# 	•	Bit 5 = 1 (supports remote wakeup)
# 	•	Meaning: Bus-powered device with remote wakeup support.
echo 0x80 > configs/c.1/bmAttributes

# Generate MAC address
cpu_serial=$(awk -F ': ' '/Serial/ {print $2}' /proc/cpuinfo)

# Generate MD5 hash of the input string
hash_host=$(echo -n "$cpu_serial-host" | md5sum | awk '{print $1}')
hash_self=$(echo -n "$cpu_serial-self" | md5sum | awk '{print $1}')

# Take the first 12 characters to form the MAC address
mac_hex_host="${hash_host:0:12}" # "HostPC"
mac_hex_self="${hash_self:0:12}" # "BadUSB"

mac_address_host=$(generate_mac "$mac_hex_host")
mac_address_self=$(generate_mac "$mac_hex_self")

echo "Generated MAC Address for host: $mac_address_host"
echo "Generated MAC Address for self: $mac_address_self"

# ECM - create ethernet configuration
mkdir -p functions/ecm.usb0
echo $mac_address_host > functions/ecm.usb0/host_addr
echo $mac_address_self > functions/ecm.usb0/dev_addr
# link function to configuration
ln -s functions/ecm.usb0 configs/c.1/

## This section is for Windows
# RNDIS -  
#mkdir -p configs/c.2
#echo 0x80 > configs/c.2/bmAttributes
#echo 0x250 > configs/c.2/MaxPower
#mkdir -p configs/c.2/strings/0x409
#echo "RNDIS" > configs/c.2/strings/0x409/configuration

#echo "1" > os_desc/use
#echo "0xcd" > os_desc/b_vendor_code
#echo "MSFT100" > os_desc/qw_sign
     
#mkdir -p functions/rndis.usb0
#HOST_R="00:dc:c8:f7:75:16"
#SELF_R="00:dd:dc:eb:6d:a2"
#echo $HOST_R > functions/rndis.usb0/dev_addr
#echo $SELF_R > functions/rndis.usb0/host_addr
#echo "RNDIS" >   functions/rndis.usb0/os_desc/interface.rndis/compatible_id
#echo "5162001" > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id
     
#ln -s functions/rndis.usb0 configs/c.2
#ln -s configs/c.2 os_desc

############## end of windows section
      
# Add a more robust UDC detection and activation
UDC=$(ls /sys/class/udc | head -n 1)
if [ -z "$UDC" ]; then
    echo "No UDC driver found"
    exit 1
fi

# Ensure clean state before activation
echo "" > UDC
sleep 1
echo "$UDC" > UDC

# Increase settle time and add retry logic
udevadm settle -t 10 || :
sleep 2

# Restart NetworkManager to ensure interface is properly configured
systemctl restart NetworkManager
sleep 5

# Bring up network connections with retry logic
for i in {1..3}; do
    nmcli connection up bridge-br0 && break
    echo "Retry $i: Bringing up bridge-br0"
    sleep 2
done

for i in {1..3}; do
    nmcli connection up bridge-slave-usb0 && break
    echo "Retry $i: Bringing up bridge-slave-usb0"
    sleep 2
done

# Check if br0 exists, create it if it doesn't
if ! nmcli connection show | grep -q "br0"; then
    nmcli con add type bridge ifname br0
    echo "Bridge br0 created."
else
    echo "Bridge br0 already exists."
fi

# Check if bridge-slave connection for usb0 exists, add it if it doesn't
if ! nmcli connection show | grep -q "bridge-slave-usb0"; then
    nmcli con add type bridge-slave ifname usb0 master br0
    echo "Bridge-slave connection for usb0 added."
else
    echo "Bridge-slave connection for usb0 already exists."
fi
# Check if bridge-slave connection for usb0 exists, add it if it doesn't
if ! nmcli connection show | grep -q "bridge-slave-usb1"; then
    nmcli con add type bridge-slave ifname usb1 master br0
    echo "Bridge-slave connection for usb1 added."
else
    echo "Bridge-slave connection for usb1 already exists."
fi

# First try DHCP client mode
nmcli connection modify bridge-br0 ipv4.method auto

# Add static IP as first fallback
# nmcli connection modify bridge-br0 +ipv4.method manual
# nmcli connection modify bridge-br0 ipv4.addresses "10.55.0.1/24"  # Choose your preferred IP

# Add link-local addressing as fallback
# This ensures the Pi gets a 169.254.x.x address even without DHCP
# nmcli connection modify bridge-br0 +ipv4.method link-local

# Enable connection sharing on the Mac-facing interface
# This makes the Pi try to auto-configure networking when connected
nmcli connection modify bridge-br0 connection.autoconnect yes
nmcli connection modify bridge-br0 connection.autoconnect-priority 10

# Setting up a network bridge between the windows and ecm interfaces so they use the same IP address
# starting Pi5 with the Bookworm distribution, Network Manager (nmcli) is used instead of dhcpd
nmcli connection up bridge-br0
nmcli connection up bridge-slave-usb0
#nmcli connection up bridge-slave-usb1


