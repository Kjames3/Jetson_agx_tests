# Jetson AGX Orin seller inspection

Copy this folder to the Jetson. Run from a writable drive:
```bash
bash jetson-check.sh
bash jetson-check.sh --demo --source 0 --seconds 300
# Or use a long local video, without a desktop:
bash jetson-check.sh --demo --source test.mp4 --seconds 300 --headless
```
Reports go in reports/. The demo saves detection.jpg and prints measured FPS.
Q closes the preview. Inspection does not install software, change clocks, flash,
or write raw disks. Missing commands/permissions are UNVERIFIED, not hardware failures.
Inventory-only exit code is not a hardware verdict.

## Automatic setup (JetPack 5 or 6)
On the Jetson, with internet access:
```bash
bash setup-jetson.sh
bash jetson-check.sh --demo --source 0 --seconds 300
```
Setup installs Docker, NVIDIA container tooling and inspection utilities through apt,
downloads the matching Ultralytics image and yolo11n.pt, and verifies CUDA inference.
It requires sudo and several GB of disk space/downloads. It may restart Docker when
registering the NVIDIA runtime, interrupting existing containers.
System Python packages are untouched. Unsupported L4T releases stop before installing.
The image ID is saved locally; rerun setup on each Jetson. After setup, the demo can
run offline. Use local videos inside this folder (container paths start at /work).
Desktop preview requires X11/XWayland and a readable XAUTHORITY; otherwise use
--headless. USB cameras are supported; CSI/Argus cameras need separate integration.
Direct demo command: `bash run-yolo.sh --source 0`.
The inspection script automatically selects the container after successful setup.
Optional native Python/TensorRT commands below require a separate native environment.

## Prepare before the visit
Ask the seller for their JetPack/L4T version, exact module and carrier-board model,
a photo of the module label, and permission for a 20–30 minute test.
Have them prepare working CUDA-enabled PyTorch, torchvision, OpenCV and Ultralytics
using the instructions for their exact JetPack:
https://docs.ultralytics.com/guides/nvidia-jetson/
Do not blindly upgrade system PyTorch with pip on a Jetson.

In that environment, while internet is available, download weights:
```bash
python3 -c "from ultralytics import YOLO; YOLO('yolo11n.pt')"
```
Keep yolo11n.pt beside the scripts. Bring a USB webcam and a local video.
Rehearse the demo on the actual Jetson environment before the appointment if possible.
A dependency failure means the GPU remains untested.

Optional TensorRT FP16 comparison, built ON the target Jetson:
```bash
yolo export model=yolo11n.pt format=engine half=True imgsz=640 device=0
bash jetson-check.sh --demo --model yolo11n.engine --source 0
```
Export needs compatible TensorRT/export dependencies and can take several minutes.
Do not copy an engine built on a different GPU/software stack.
The default .pt run uses PyTorch; it is not a maximum-performance TensorRT benchmark.
FPS includes capture, plotting and display; a 30 FPS webcam can cap it.
The separately reported inference milliseconds exclude those steps.
Compare only matching model, backend, precision, image size and power mode.

## In-person checklist
- Cold boot, reboot, and verify the desktop/display and administrator access.
- Compare the physical module label with software identity and visible RAM.
  RAM capacity alone cannot authenticate the module. OS reservations reduce visible RAM.
- Confirm this is the complete usable system: carrier, cooler/fan, correct power supply,
  storage and any claimed wireless hardware. Ask about repairs, liquid damage and history.
- Plug a known device into each USB port; test Ethernet transfer, display output,
  and Wi-Fi/Bluetooth if included. Listing interfaces does not test their operation.
- Run YOLO for at least 5–10 minutes while watching `tegrastats --interval 1000`
  in another terminal. Look for resets, artifacts, fan problems, sustained clock drops,
  and new kernel errors. Review temperatures relative to the device's thermal limits.
- Check SSD SMART/NVMe health with the appropriate installed vendor/Linux tools.
  Inventory does not test storage integrity. Avoid destructive disk tests.
- A full RAM test and sustained CPU/GPU stress test require additional time and tools;
  this smoke test does not certify every memory cell, GPU unit or connector.
- Record serial numbers on the bill of sale and clarify return terms before payment.

$1500 alone cannot establish authenticity or value. Compare current local complete-kit
offers, condition, included hardware and return rights. Be prepared to postpone purchase
if the seller cannot demonstrate CUDA working or refuses basic inspection.

## Validation
Shell syntax and Python CLI checked on the development host. No Jetson hardware
validation has been performed; actual FPS must be measured on the seller's unit.

## Verified on the robot (2026-10-31)
Orin Nano 8GB, L4T 36.4.7, native Torch 2.10.0 / Ultralytics 8.4.24:
Astra Pro USB RGB camera, 640 input, 584 frames in 30.01s = 19.46 loop FPS;
32.00 ms mean model inference. ROS processes were running concurrently.
Desktop window and saved detections verified. Container setup remains unverified.

If CUDA PyTorch, OpenCV and Ultralytics are already installed:
```bash
bash setup-jetson.sh --native
DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority python3 demo.py --seconds 300
```
Native setup downloads the weights and tests GPU inference; it does not install
missing Python packages. Display/auth values above apply to the tested robot session.

## Small-screen demo
The preview now defaults to a resizable 1280-pixel window with a large timing panel.
For a small attached screen:
```bash
bash jetson-check.sh --demo --source 0 --seconds 600 --fullscreen
```
Use Q or Esc to quit. Fullscreen changes presentation, not the 640 model input.
With native dependencies use `python3 demo.py --fullscreen --seconds 600`.

## Clean installation after purchase
`agx-factory-reset.sh` is a HOST-PC guide/SDK Manager launcher, not an on-device
erase command. It refuses to run on Jetsons. See its instructions, then optionally
use `bash agx-factory-reset.sh --launch` on the host. The SDK Manager UI performs
the actual flash after you select the correct hardware and storage.
This cannot reproduce an unknown original factory image or reset security fuses.
No reset/recovery operations were tested on the Nano.

## Display troubleshooting
The demo discovers a single local X11 display and the current user's GDM
authorization file when SSH does not supply DISPLAY/XAUTHORITY. It probes OpenCV
in a separate process before loading the model, so display failures produce a
clear error instead of aborting the demo. This does not start a desktop or bypass
display permissions. Log into the attached desktop as the same user, or use
--headless to measure FPS and save a detection image without a window.
Copy display_check.py alongside demo.py when transferring the package.

## Bundled test videos (default source)
With no `--source`, the demo plays every clip in `videos/` in turn, looping until
`--seconds` elapses, so no camera is needed:
`bash jetson-check.sh --demo --fullscreen --seconds 600`.
Use `--source 0` for a USB camera or `--source file.mp4` for your own clip.
Clips (Intel IoT DevKit sample-videos, CC-BY 4.0,
https://github.com/intel-iot-devkit/sample-videos):
- `person-bicycle-car.mp4` from `person-bicycle-car-detection.mp4`
- `people-walking.mp4` from `people-detection.mp4`

## Offline preparation
`yolo11n.pt` is committed to the repo (Ultralytics weights, AGPL-3.0), so no
model download is needed. The weights work on JetPack 5 and 6.

The Docker setup still needs the Ultralytics Jetson image. To avoid downloading
several GB at the inspection, save it beforehand on a Jetson with internet:
```bash
bash setup-jetson.sh --save-image 6   # new AGX kits usually ship JetPack 6
bash setup-jetson.sh --save-image 5   # older stock may have JetPack 5
```
Copy `images/` (not committed) onto an exFAT or ext4 USB stick next to the repo.
FAT32 cannot hold files over 4 GB. On the AGX, `bash setup-jetson.sh` loads the
matching `images/ultralytics-jetpackN.tar` and only uses apt when Docker or the
NVIDIA container toolkit is missing.
