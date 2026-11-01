#!/usr/bin/env bash
# Guided reinstallation launcher. Run on the HOST PC, never on the Jetson.
set -euo pipefail
if [[ $(uname -m) == aarch64 || -e /etc/nv_tegra_release ]]; then
  echo "REFUSED: run this helper on your host PC, not on any Jetson."
  exit 1
fi
cat <<'GUIDE'
AGX Orin clean-install helper
A factory-like software reset requires reflashing JetPack. This is not an
in-place reset, secure erase, or a way to undo hardware changes/security fuses.
Do this after purchase, with backups and stable power.

1. Disconnect every other Jetson, especially your Orin Nano.
2. Identify the AGX module AND carrier. Third-party carriers may require their
   vendor BSP; do not flash a generic developer-kit image onto those blindly.
3. Install NVIDIA SDK Manager on a supported host OS for your chosen JetPack.
4. Connect the AGX's recovery USB port to this host using a data cable.
5. Put ONLY the AGX into Force Recovery using its documented button sequence.
6. In SDK Manager verify the detected AGX Orin and choose JetPack and target
   storage deliberately. Flashing overwrites selected storage. Other disks
   may retain old data; this helper does not erase them.
7. Complete first-boot setup and install JetPack components.

Official instructions:
https://docs.nvidia.com/jetson/agx-orin-devkit/user-guide/setup_bsp.html
https://developer.nvidia.com/sdk-manager

This helper only opens SDK Manager. Review the target in its UI before flashing.
GUIDE
if [[ ${1:-} != --launch ]]; then
  echo "To open installed SDK Manager: bash agx-factory-reset.sh --launch"
  exit 0
fi
command -v sdkmanager >/dev/null || { echo "Install SDK Manager first."; exit 1; }
read -r -p "Type AGX ONLY after disconnecting the Nano: " confirmation
[[ $confirmation == "AGX ONLY" ]] || { echo "Cancelled."; exit 1; }
exec sdkmanager
