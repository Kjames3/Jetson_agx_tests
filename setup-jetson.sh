#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ ${1:-} == --help ]]; then
  echo "Usage: bash setup-jetson.sh (on JetPack 5/6 Jetson, internet required)"
  exit 0
fi
[[ $# == 0 ]] || { echo "Unknown argument"; exit 2; }
[[ $(uname -m) == aarch64 && -f /etc/nv_tegra_release ]] ||
  { echo "Run this on the Jetson, not your PC."; exit 1; }
release=$(sed -n 's/^# R\([0-9]*\).*/\1/p' /etc/nv_tegra_release)
case "$release" in
  35) jp=5 ;;
  36) jp=6 ;;
  *) echo "Unsupported L4T R$release. Setup supports JetPack 5/6 only."; exit 1 ;;
esac
root=()
(( EUID == 0 )) || root=(sudo)
echo "Installing Docker/runtime and inspection utilities; downloading a multi-GB YOLO image."
"${root[@]}" apt-get update
"${root[@]}" apt-get install -y docker.io nvidia-container-toolkit usbutils iproute2
"${root[@]}" systemctl start docker
if ! "${root[@]}" docker info --format '{{json .Runtimes}}' | grep -q '"nvidia"'; then
  "${root[@]}" nvidia-ctk runtime configure --runtime=docker
  echo "Restarting Docker to enable the NVIDIA runtime."
  "${root[@]}" systemctl restart docker
fi
image="ultralytics/ultralytics:latest-jetson-jetpack$jp"
"${root[@]}" docker pull "$image"
image_id=$("${root[@]}" docker image inspect --format '{{.Id}}' "$image")
mkdir -p reports
"${root[@]}" docker run --rm --runtime=nvidia --ipc=host   --user "$(id -u):$(id -g)" -e HOME=/tmp -e YOLO_CONFIG_DIR=/tmp/yolo   -v "$PWD:/work" -w /work "$image_id" python3 -c '
import torch, cv2, numpy as np
from ultralytics import YOLO
assert torch.cuda.is_available(), "CUDA unavailable in container"
model = YOLO("yolo11n.pt")
model.predict(np.zeros((640,640,3), dtype=np.uint8), device=0, verbose=False)
torch.cuda.synchronize()
print("CUDA YOLO smoke test passed:", torch.cuda.get_device_name(0))
'
printf '%s\n' "$image_id" > .jetson-image
echo "Ready: bash run-yolo.sh --source 0 --seconds 300"
