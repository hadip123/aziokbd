#!/bin/bash
set -euo pipefail

MODULE_NAME="aziokbd"
MODULE_VER="1.0.0"
VENDOR_ID="0x0c45"
PRODUCT_ID="0x7603"
QUIRK="${VENDOR_ID}:${PRODUCT_ID}:0x0007"
MODPROBE_CONF="/etc/modprobe.d/usbhid.conf"
BOOT_ENTRIES="/boot/loader/entries"

die() { echo "ERROR: $*" >&2; exit 1; }

check_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root."
}

check_source() {
    [[ -f Makefile ]] || die "Run this script from the aziokbd source directory."
}

install_deps() {
    echo "## Installing dependencies ##"
    pacman -S --needed --noconfirm base-devel linux-headers dkms
}

ask_backslash_fix() {
    read -n 1 -p "Backslash fix (y/N)? " choice
    echo
    case "$choice" in
        y|Y) BKSL="BKSLFIX=y" ;;
        *) BKSL="BKSLFIX=n" ;;
    esac
}

configure_quirks() {
    if grep -q "^usbhid" /lib/modules/"$(uname -r)"/modules.builtin 2>/dev/null; then
        echo "## usbhid is compiled into kernel ##"
        echo "## Configuring systemd-boot kernel parameters ##"

        if [[ ! -d "$BOOT_ENTRIES" ]]; then
            die "systemd-boot entries directory not found at $BOOT_ENTRIES"
        fi

        for entry in "$BOOT_ENTRIES"/*.conf; do
            [[ -f "$entry" ]] || continue
            if grep -q "usbhid.quirks" "$entry"; then
                echo "NOTICE - $entry already has usbhid.quirks"
            else
                echo "## Appending quirk to $entry ##"
                sed -i "/^options/s/$/ usbhid.quirks=${QUIRK}/" "$entry"
            fi
        done

        echo "## You must reboot to load the module ##"
    else
        echo "## usbhid is a module ##"

        if [[ -f "$MODPROBE_CONF" ]] && grep -q "$QUIRK" "$MODPROBE_CONF"; then
            echo "NOTICE - modprobe config already has the quirk"
        else
            echo "## Writing to $MODPROBE_CONF ##"
            echo "options usbhid quirks=${QUIRK}" >> "$MODPROBE_CONF"
        fi

        echo "## Loading aziokbd module ##"
        modprobe "$MODULE_NAME" || true

        echo "## Reloading usbhid with quirks ##"
        if ! rmmod usbhid 2>/dev/null; then
            echo "WARNING: Could not unload usbhid (dependents loaded?). Reboot to apply quirk."
        fi
        modprobe usbhid || true
    fi
}

install_dkms() {
    echo "## Installing with DKMS ##"
    sed -i '/MAKE\[0\]/d' dkms.conf
    sed -i "\$aMAKE[0]=\"make ${BKSL}\"" dkms.conf
    make "${BKSL}" dkms
    configure_quirks
}

install_manual() {
    echo "## Building module ##"
    make "${BKSL}"

    echo "## Installing module ##"
    make install

    echo "## Creating systemd modules-load config ##"
    mkdir -p /etc/modules-load.d
    echo "$MODULE_NAME" > "/etc/modules-load.d/${MODULE_NAME}.conf"

    configure_quirks
}

main() {
    check_root
    check_source
    install_deps
    ask_backslash_fix

    if [[ "${1:-}" == "dkms" ]]; then
        install_dkms
    else
        install_manual
    fi

    echo ""
    echo "## Installation complete ##"
    echo "Module: ${MODULE_NAME} ${MODULE_VER}"
    echo "Device: ${VENDOR_ID}:${PRODUCT_ID}"
}

main "$@"
