#!/bin/bash -e

echo "################### 'murikaaaaa' ###################"
echo "Installing USB gadget..."
echo "################### 'murikaaaaa' ###################"

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
    SUDO_USER="${FIRST_USER_NAME}" echo "usb_f_ecm" >> /etc/modules
EOF

install -m 755 files/usb-gadget.sh "${ROOTFS_DIR}/usr/local/sbin/"
install -m 644 files/usbgadget.service "${ROOTFS_DIR}/lib/systemd/system/"
install -m 644 files/br0 "${ROOTFS_DIR}/etc/dnsmasq.d/"

## for dynamic IP allocation
# sudo nmcli connection modify bridge-br0 ipv4.method auto
on_chroot << EOF
echo "Enabling USB gadget service..."
systemctl enable usbgadget.service
EOF
