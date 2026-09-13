#!/bin/bash
#========================================================================================
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# Derived from: https://github.com/ophub/amlogic-s9xxx-armbian
#               (build-armbian/armbian-files/common-files/etc/custom_service/start_service.sh)
# Trimmed for amlogic-rebuild: 仅保留 Phicomm-N1 / CM311-1a-YST / M302A / WXY-OES
# 运行所必要的启动项, 移除 armbian 生态与其他机型的内容。
#
# Function: Customize the startup script. Add content as needed.
# Dependent script: /etc/rc.local (which runs with 'set -e')
# File path: /etc/custom_service/start_service.sh
#
#========================================================================================

set +euo pipefail

trap 'exit 0' EXIT

# Custom Service Log - all script output will be logged here
custom_log="/tmp/ophub_start_service.log"

# A helper function for logging with a timestamp
log_message() {
    echo "[$(date +"%Y.%m.%d.%H:%M:%S")] $1" >>"${custom_log}" 2>/dev/null || true
}

# Start of the script
log_message "Starting custom services..."

# Disabled verbose kernel messages on console
dmesg -n 1 >/dev/null 2>&1 || true
log_message "Kernel console logging level set to 1 (Panic only)."

# Search for the FDTFILE file (only the basename of the .dtb is needed)
FDTFILE=""
# 1) /boot/uEnv.txt : FDT=/dtb/.../xxx.dtb  (or FDT=xxx.dtb)
[[ -z "${FDTFILE}" && -f "/boot/uEnv.txt" ]] &&
    FDTFILE="$(grep -E '^FDT=.*\.dtb$' /boot/uEnv.txt 2>/dev/null | head -n1 | sed -E 's#^FDT=##; s#.*/##')"
log_message "Detected FDT file: ${FDTFILE:-not found}"

# Device-Specific Services

# For oes(A311d) SATA LED status monitoring (WXY-OES)
if [[ "${FDTFILE}" == "meson-g12b-a311d-oes-a.dtb" && -x "/usr/bin/oes_sata_leds.sh" ]]; then
    /usr/bin/oes_sata_leds.sh >/var/log/oes-sata-leds.log 2>&1 &
    log_message "SATA status check service (oes_sata_leds.sh) started in background."
fi

# General System Services

# Prepare sshd runtime dir
mkdir -p -m0755 /var/run/sshd >/dev/null 2>&1 || true

# Add network performance optimization (NIC IRQ affinity)
if [[ -x "/usr/sbin/balethirq.pl" ]]; then
    (perl /usr/sbin/balethirq.pl >/dev/null 2>&1) &
    log_message "Network optimization service (balethirq.pl) execution attempted."
fi

# Enable UDP GRO forwarding on all physical ethernet interfaces
# View command: ethtool -k eth0 | grep -i udp
if command -v ethtool >/dev/null 2>&1; then
    shopt -s nullglob
    for iface in /sys/class/net/*/device; do
        iface_name="$(basename "${iface%/device}")"
        # Skip non-ethernet interfaces (type != 1) and wireless interfaces
        [[ "$(cat /sys/class/net/${iface_name}/type 2>/dev/null)" != "1" ]] && continue
        [[ -d "/sys/class/net/${iface_name}/wireless" ]] && continue
        ethtool -K "${iface_name}" rx-udp-gro-forwarding on >/dev/null 2>&1
        log_message "Enabled rx-udp-gro-forwarding on ${iface_name}."
    done
    shopt -u nullglob
fi

# Finalization
log_message "All custom services have been processed successfully."
trap '' HUP INT QUIT TERM PIPE
exit 0
