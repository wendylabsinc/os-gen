#!/bin/bash -e

SWIFT_VERSION="6.0.3"

echo "################### 'EdgeOS' ###################"
echo "Setting up EdgeOS version information..."
echo "################### 'EdgeOS' ###################"

# Create EdgeOS version files
install -d "${ROOTFS_DIR}/etc/edgeos"

# Create temporary files
echo "EdgeOS-${EDGEOS_BUILD_HASH}" > /tmp/edgeos-build-id
echo "-EdgeOS-${EDGEOS_BUILD_HASH}" > /tmp/localversion

# Install files with proper permissions
install -m 644 /tmp/edgeos-build-id "${ROOTFS_DIR}/etc/edgeos-build-id"
install -m 644 /tmp/localversion "${ROOTFS_DIR}/etc/localversion"

# Clean up temporary files
rm /tmp/edgeos-build-id /tmp/localversion

# Install MOTD header
install -d "${ROOTFS_DIR}/etc/update-motd.d"
install -m 755 files/10-edgeos-header "${ROOTFS_DIR}/etc/update-motd.d/10-edgeos-header"

echo "################### 'EdgeOS' ###################"
echo "Setting up generate-uuid.sh..."
echo "################### 'EdgeOS' ###################"

# Create directory for UUID file
install -d "${ROOTFS_DIR}/etc/edgeos"
install -m 755 files/generate-uuid.sh "${ROOTFS_DIR}/usr/local/sbin/"

echo "################### 'EdgeOS' ###################"
echo "Installing USB gadget..."
echo "################### 'EdgeOS' ###################"

CMDLINE="/boot/firmware/cmdline.txt"
on_chroot <<- EOF
    do_add_dwc2_cmdline() {
        if ! grep -q "modules-load=dwc2" ${CMDLINE}; then
            sed -i "s/$/ modules-load=dwc2/" ${CMDLINE}
        fi
    }
    set -x  # Enable script debugging
    echo "SUDO_USER='${FIRST_USER_NAME}'"
    SUDO_USER="${FIRST_USER_NAME}" do_add_dwc2_cmdline

    SUDO_USER="${FIRST_USER_NAME}" echo "libcomposite" >> /etc/modules
    SUDO_USER="${FIRST_USER_NAME}" echo "usb_f_ncm" >> /etc/modules
EOF

install -m 755 files/usb-gadget.sh "${ROOTFS_DIR}/usr/local/sbin/"
install -m 644 files/usbgadget.service "${ROOTFS_DIR}/lib/systemd/system/"
# install -m 644 files/br0 "${ROOTFS_DIR}/etc/dnsmasq.d/"

## for dynamic IP allocation
# sudo nmcli connection modify bridge-br0 ipv4.method auto
on_chroot << EOF
echo "Enabling USB gadget service..."
systemctl enable usbgadget.service
EOF

echo "################### 'EdgeOS' ###################"
echo "Setting up avahi-daemon..."
echo "################### 'EdgeOS' ###################"

# Create avahi services directory
install -d "${ROOTFS_DIR}/etc/avahi/services"

# Install DNS service file
install -m 644 files/edgeos-dns.service "${ROOTFS_DIR}/etc/avahi/services/"
install -m 755 files/update-dns-service.sh "${ROOTFS_DIR}/usr/local/sbin/"

on_chroot << EOF
echo "Enabling avahi-daemon service..."
systemctl enable avahi-daemon.service
EOF

echo "################### 'EdgeOS' ###################"
echo "Installing USB gadget resume handler..."
echo "################### 'EdgeOS' ###################"

# Install udev rule and resume script
install -m 644 files/90-usb-gadget.rules "${ROOTFS_DIR}/etc/udev/rules.d/"
install -m 755 files/usb-gadget-resume.sh "${ROOTFS_DIR}/usr/local/sbin/"

# Only copy wpa_supplicant.conf if DEVELOPMENT is set
if [ "${DEVELOPMENT:-}" = "true" ]; then
    echo "################### 'EdgeOS' ###################"
    echo "Installing development WiFi configuration..."
    echo "################### 'EdgeOS' ###################"
    
    # Create directory if it doesn't exist
    install -d "${ROOTFS_DIR}/etc/wpa_supplicant"
    
    # Copy the configuration file
    install -m 600 files/wpa_supplicant.conf "${ROOTFS_DIR}/etc/wpa_supplicant/"

    # Only add SSH key if DEVELOPMENT is set
    echo "################### 'EdgeOS' ###################"
    echo "Installing development SSH key..."
    echo "################### 'EdgeOS' ###################"
    
    # Create .ssh directory for first user
    install -d -m 700 "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.ssh"
    
    # Copy authorized_keys file
    install -m 600 files/authorized_keys "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.ssh/"
    
    # Set correct ownership
    on_chroot << EOF
        chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME} /home/${FIRST_USER_NAME}/.ssh
EOF
fi

echo "################### 'EdgeOS' ###################"
echo "Done"
echo "################### 'EdgeOS' ###################"