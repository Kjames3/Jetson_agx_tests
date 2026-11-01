#!/usr/bin/env python3
"""Local camera/video YOLO smoke test; no automatic package installation."""
import argparse
import time
from pathlib import Path

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--source", default="0", help="USB camera index, local video (loops), or stream URL")
    p.add_argument("--model", default="yolo11n.pt", help="Local weights or TensorRT engine")
    p.add_argument("--seconds", type=float, default=60)
    p.add_argument("--headless", action="store_true")
    p.add_argument("--fullscreen", action="store_true", help="Fill the attached display")
    p.add_argument("--window-width", type=int, default=1280)
    args = p.parse_args()
    if args.window_width < 320:
        p.error("--window-width must be at least 320")
    if args.seconds <= 0:
        p.error("--seconds must be positive")
    if not Path(args.model).is_file():
        p.error("Model missing: pre-download yolo11n.pt before visiting the seller")
    if not args.headless:
        from display_check import prepare_display
        try:
            prepare_display()
        except RuntimeError as exc:
            p.exit(2, f"Display unavailable: {exc}\n")
    import cv2
    import numpy as np
    window = "Jetson YOLO - Q or Esc to quit"

    def status(msg):
        # Print each stage and paint it on screen so a slow start never looks like a hang.
        print(msg, flush=True)
        if args.headless:
            return
        splash = np.zeros((540, 960, 3), np.uint8)
        cv2.putText(splash, "Jetson YOLO demo", (40, 120), cv2.FONT_HERSHEY_SIMPLEX, 1.6, (0, 255, 0), 3)
        cv2.putText(splash, msg[:60], (40, 260), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)
        cv2.putText(splash, "First start can take 1-3 minutes", (40, 340), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (180, 180, 180), 2)
        cv2.imshow(window, splash)
        cv2.waitKey(1)

    if not args.headless:
        cv2.namedWindow(window, cv2.WINDOW_NORMAL | cv2.WINDOW_KEEPRATIO)
        cv2.resizeWindow(window, args.window_width, int(args.window_width * 0.75))
        if args.fullscreen:
            cv2.setWindowProperty(window, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
    status("Loading PyTorch / CUDA...")
    import torch
    from ultralytics import YOLO
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA unavailable. Use a Jetson-compatible PyTorch/JetPack environment.")
    print("GPU:", torch.cuda.get_device_name(0), "Torch:", torch.__version__)
    status(f"Loading model {args.model}...")
    model = YOLO(args.model)
    status(f"Opening camera/video source {args.source}...")
    cap = cv2.VideoCapture(int(args.source) if args.source.isdecimal() else args.source)
    is_file = Path(args.source).is_file()
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open source {args.source!r}. Check the USB camera (ls /dev/video*) or file path.")
    try:
        ok, frame = cap.read()
        if not ok:
            raise RuntimeError("Cannot read camera/video")
        for i in range(10):
            status(f"GPU warmup {i + 1}/10...")
            model.predict(frame, device=0, imgsz=640, verbose=False)
        status("Running live detection")
        torch.cuda.synchronize()
        start = time.perf_counter()
        count, inference_ms = 0, 0.0
        while time.perf_counter() - start < args.seconds:
            tick = time.perf_counter()
            ok, frame = cap.read()
            if not ok and is_file:
                # Loop video files so a short clip can drive a long stability run.
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                ok, frame = cap.read()
            if not ok:
                break
            result = model.predict(frame, device=0, imgsz=640, verbose=False)[0]
            torch.cuda.synchronize()
            inference_ms += result.speed["inference"]
            count += 1
            annotated = result.plot()
            fps = 1 / (time.perf_counter() - tick)
            # A separate high-contrast panel keeps timings clear of detection labels.
            annotated = cv2.resize(annotated, (960, round(annotated.shape[0] * 960 / annotated.shape[1])))
            annotated = cv2.copyMakeBorder(annotated, 115, 0, 0, 0, cv2.BORDER_CONSTANT)
            cv2.putText(annotated, f"FPS: {fps:.1f}   Inference: {result.speed['inference']:.1f} ms",
                        (20, 48), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (0, 255, 0), 2)
            cv2.putText(annotated, "Capture + YOLO + plot timing | Q / Esc to quit",
                        (20, 92), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
            if count == 1:
                Path("reports").mkdir(exist_ok=True)
                cv2.imwrite("reports/detection.jpg", annotated)
            if not args.headless:
                cv2.imshow(window, annotated)
                if cv2.waitKey(1) & 255 in (ord("q"), 27):
                    break
        elapsed = time.perf_counter() - start
        if not count:
            raise RuntimeError("No measured frames; use a longer video")
        print(f"{count} frames / {elapsed:.2f}s = {count/elapsed:.2f} loop FPS")
        print(f"Mean model inference: {inference_ms/count:.2f} ms (excludes capture/plot/display)")
        print("Batch=1, imgsz=640; warmup excluded. Camera frame rate may limit loop FPS.")
    finally:
        cap.release()
        cv2.destroyAllWindows()

if __name__ == "__main__":
    main()
