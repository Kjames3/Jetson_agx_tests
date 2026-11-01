#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ ${1:-} == --help ]]; then
  cat <<'USAGE'
Usage: bash setup-jetson.sh [--native | --save-image [5|6]]
  (none)          Docker setup. Loads images/ultralytics-jetpackN.tar if present
                  (offline), else pulls from the internet.
  --native        Verify an existing CUDA PyTorch + Ultralytics install.
  --save-image N  On a prep Jetson with internet: pull the JetPack N image and
                  save it to images/ for offline setup (default: this board's).
USAGE
  exit 0
fi
native=false save=false save_jp=
case ${1:-} in
  --native) native=true; shift ;;
  --save-image) save=true; shift; [[ ${1:-} =~ ^[56]$ ]] && { save_jp=$1; shift; } ;;
esac
[[ $# == 0 ]] || { echo "Unknown argument"; exit 2; }
[[ $(uname -m) == aarch64 && -f /etc/nv_tegra_release ]] ||
  { echo "Run this on the Jetson, not your PC."; exit 1; }
release=$(sed -n 's/^# R\([0-9]*\).*/\1/p' /etc/nv_tegra_release)
case "$release" in
  35) jp=5 ;;
  36) jp=6 ;;
  *) echo "Unsupported L4T R$release. Setup supports JetPack 5/6 only."; exit 1 ;;
esac
echo "Detected L4T R$release (JetPack $jp)"
[[ -f yolo11n.pt ]] && echo "yolo11n.pt present (bundled; no model download needed)"
if $native; then
  python3 -c '
import torch, cv2, numpy as np
from ultralytics import YOLO
assert torch.cuda.is_available(), "Install JetPack-compatible CUDA PyTorch first"
print("Downloading/loading yolo11n.pt...", flush=True)
model = YOLO("yolo11n.pt")
model.predict(np.zeros((640,640,3), dtype=np.uint8), device=0, verbose=False)
torch.cuda.synchronize()
print("CUDA YOLO smoke test passed:", torch.cuda.get_device_name(0))
'
  echo "Ready: bash jetson-check.sh --demo --fullscreen --seconds 600"
  exit 0
fi
root=()
(( EUID == 0 )) || root=(sudo)
# Only touch apt (needs internet) when something is actually missing.
packages=()
command -v nvidia-ctk >/dev/null || packages+=(nvidia-container-toolkit)
command -v lsusb >/dev/null || packages+=(usbutils)
command -v docker >/dev/null || packages+=(docker.io)
if (( ${#packages[@]} )); then
  echo "Installing: ${packages[*]} (needs internet)"
  "${root[@]}" apt-get update
  "${root[@]}" apt-get install -y "${packages[@]}"
fi
"${root[@]}" systemctl start docker
if ! "${root[@]}" docker info --format '{{json .Runtimes}}' | grep -q '"nvidia"'; then
  "${root[@]}" nvidia-ctk runtime configure --runtime=docker
  echo "Restarting Docker to enable the NVIDIA runtime."
  "${root[@]}" systemctl restart docker
fi
if $save; then
  jp=${save_jp:-$jp}
  image="ultralytics/ultralytics:latest-jetson-jetpack$jp"
  tar="images/ultralytics-jetpack$jp.tar"
  mkdir -p images
  "${root[@]}" docker pull "$image"
  echo "Saving $image to $tar (several GB; copy to an exFAT/ext4 stick, not FAT32)"
  "${root[@]}" docker save -o "$tar" "$image"
  "${root[@]}" chown "$(id -u):$(id -g)" "$tar"
  ls -lh "$tar"
  echo "For a FAT32 stick: split -b 3900M $tar $tar.part-"
  exit 0
fi
image="ultralytics/ultralytics:latest-jetson-jetpack$jp"
tar="images/ultralytics-jetpack$jp.tar"
parts=("$tar".part-*)
if [[ -f $tar ]]; then
  echo "Loading $tar (offline)..."
  "${root[@]}" docker load -i "$tar"
elif [[ -f ${parts[0]} ]]; then
  # FAT32 sticks cap files at 4 GB; stream split parts without rejoining on disk.
  echo "Loading ${#parts[@]} parts of $tar (offline)..."
  cat "${parts[@]}" | "${root[@]}" docker load
else
  echo "No $tar; pulling a multi-GB image from the internet."
  "${root[@]}" docker pull "$image"
fi
image_id=$("${root[@]}" docker image inspect --format '{{.Id}}' "$image")
mkdir -p reports
"${root[@]}" docker run --rm --runtime=nvidia --ipc=host   --user "$(id -u):$(id -g)" -e HOME=/tmp -e YOLO_CONFIG_DIR=/tmp/yolo   -v "$PWD:/work" -w /work "$image_id" python3 -c '
import torch, cv2, numpy as np
from ultralytics import YOLO
assert torch.cuda.is_available(), "CUDA unavailable in container"
print("Downloading/loading YOLO11n in the project folder...", flush=True)
model = YOLO("yolo11n.pt")
model.predict(np.zeros((640,640,3), dtype=np.uint8), device=0, verbose=False)
torch.cuda.synchronize()
print("CUDA YOLO smoke test passed:", torch.cuda.get_device_name(0))
'
printf '%s\n' "$image_id" > .jetson-image
echo "Ready: bash jetson-check.sh --demo --fullscreen --seconds 600"
