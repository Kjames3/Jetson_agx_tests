#!/usr/bin/env bash
set -uo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ ${1:-} == --help ]]; then
  echo "Usage: bash jetson-check.sh [--demo [demo.py options]]"; exit 0
fi
mkdir -p reports
report="reports/check-$(date +%Y%m%d-%H%M%S)-$$.log"
exec > >(tee "$report") 2>&1
echo "Jetson pre-purchase inspection — $(date -Is)"
echo "Report: $report"
check() {
  echo; echo "=== $1 ==="; shift
  "$@" || echo "UNVERIFIED: command failed or requires permissions/dependencies"
}
check "Architecture" uname -a
check "Board identity" bash -c 'tr "\0" "\n" < /proc/device-tree/model'
check "Compatible identifiers" bash -c 'tr "\0" "\n" < /proc/device-tree/compatible'
check "L4T release" cat /etc/nv_tegra_release
check "Memory (RAM is shared with GPU)" free -h
awk '/MemTotal/ {printf "Visible RAM: %.1f GiB\n", $2/1048576; if ($2 < 55000000) print "REVIEW: less RAM than expected for a 64GB unit"}' /proc/meminfo
check "CPU" lscpu
check "Storage inventory" lsblk -o NAME,SIZE,MODEL,TYPE,MOUNTPOINTS
check "Filesystem space" df -h
check "USB (plug devices into each port)" lsusb -t
check "Network interfaces" ip -brief address
check "Power mode (read only)" nvpmodel -q
check "Clocks (read only)" jetson_clocks --show
check "Recent kernel messages" bash -c 'dmesg --level=err,warn | tail -80'
check "Telemetry, 5 seconds" timeout 5 tegrastats --interval 1000
echo "NOTE: timeout status above is expected for tegrastats."
echo "No overall PASS: ports, full RAM, storage health and sustained stability still need testing."
if [[ ${1:-} == --demo ]]; then
  shift
  if [[ -s .jetson-image ]]; then
    bash run-yolo.sh "$@"
  else
    python3 demo.py "$@"
  fi
  exit $?
elif [[ $# -gt 0 ]]; then
  echo "Unknown option; use --help"; exit 2
fi
