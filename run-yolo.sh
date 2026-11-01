#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ ${1:-} == --help ]]; then
  echo "Usage: bash run-yolo.sh [demo.py options]; run setup-jetson.sh first."
  exit 0
fi
[[ -s .jetson-image ]] || { echo "Run bash setup-jetson.sh first."; exit 1; }
image=$(cat .jetson-image)
[[ $image =~ ^sha256:[a-f0-9]{64}$ ]] || { echo "Invalid image ID"; exit 1; }
root=()
(( EUID == 0 )) || root=(sudo)
args=(--rm --runtime=nvidia --ipc=host --user "$(id -u):$(id -g)"
      -e HOME=/tmp -e YOLO_CONFIG_DIR=/tmp/yolo -v "$PWD:/work" -w /work)
for device in /dev/video*; do
  [[ -e $device ]] || continue
  args+=(--device "$device" --group-add "$(stat -c %g "$device")")
done
headless=false
for arg in "$@"; do [[ $arg != --headless ]] || headless=true; done
if ! $headless; then
  [[ -n ${DISPLAY:-} ]] || { echo "No display; pass --headless."; exit 1; }
  auth=${XAUTHORITY:-$HOME/.Xauthority}
  [[ -r $auth ]] || { echo "No readable Xauthority; use --headless or set XAUTHORITY."; exit 1; }
  args+=(-e DISPLAY -e XAUTHORITY=/tmp/xauth
         -v "$auth:/tmp/xauth:ro" -v /tmp/.X11-unix:/tmp/.X11-unix:ro)
fi
mkdir -p reports
"${root[@]}" docker run "${args[@]}" "$image" python3 demo.py "$@"
