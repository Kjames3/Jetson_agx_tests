#!/usr/bin/env python3
"""Local camera/video YOLO smoke test; no automatic package installation."""
import argparse
import time
from pathlib import Path

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--source", default="0", help="USB camera index or local video")
    p.add_argument("--model", default="yolo11n.pt", help="Local weights or TensorRT engine")
    p.add_argument("--seconds", type=float, default=60)
    p.add_argument("--headless", action="store_true")
    args = p.parse_args()
    if args.seconds <= 0:
        p.error("--seconds must be positive")
    if not Path(args.model).is_file():
        p.error("Model missing: pre-download yolo11n.pt before visiting the seller")
    import cv2
    import torch
    from ultralytics import YOLO
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA unavailable. Use a Jetson-compatible PyTorch/JetPack environment.")
    print("GPU:", torch.cuda.get_device_name(0), "Torch:", torch.__version__)
    model = YOLO(args.model)
    cap = cv2.VideoCapture(int(args.source) if args.source.isdecimal() else args.source)
    try:
        ok, frame = cap.read()
        if not ok:
            raise RuntimeError("Cannot read camera/video")
        for _ in range(10):
            model.predict(frame, device=0, imgsz=640, verbose=False)
        torch.cuda.synchronize()
        start = time.perf_counter()
        count, inference_ms = 0, 0.0
        while time.perf_counter() - start < args.seconds:
            tick = time.perf_counter()
            ok, frame = cap.read()
            if not ok:
                break
            result = model.predict(frame, device=0, imgsz=640, verbose=False)[0]
            torch.cuda.synchronize()
            inference_ms += result.speed["inference"]
            count += 1
            annotated = result.plot()
            fps = 1 / (time.perf_counter() - tick)
            cv2.putText(annotated, f"Capture+YOLO+plot: {fps:.1f} FPS", (15, 35),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
            if count == 1:
                Path("reports").mkdir(exist_ok=True)
                cv2.imwrite("reports/detection.jpg", annotated)
            if not args.headless:
                cv2.imshow("Jetson YOLO — Q to quit", annotated)
                if cv2.waitKey(1) & 255 == ord("q"):
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
