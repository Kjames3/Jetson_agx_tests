"""Find the user's local X11 desktop and isolate Qt initialization failures."""
import os
import subprocess
import sys
from pathlib import Path


def prepare_display():
    if not os.environ.get("DISPLAY"):
        sockets = sorted(Path("/tmp/.X11-unix").glob("X[0-9]*"))
        if len(sockets) == 1:
            os.environ["DISPLAY"] = ":" + sockets[0].name[1:]
    if not os.environ.get("XAUTHORITY"):
        for auth in (Path(f"/run/user/{os.getuid()}/gdm/Xauthority"),
                     Path.home() / ".Xauthority"):
            if auth.is_file() and os.access(auth, os.R_OK):
                os.environ["XAUTHORITY"] = str(auth)
                break
    if not os.environ.get("DISPLAY"):
        raise RuntimeError("No desktop display found. Log into the attached screen and "
                           "run from its terminal, or pass --headless.")
    # Qt can abort the process rather than raise an exception. Probe in a child
    # before opening the camera or loading GPU weights; disable core dumps there.
    code = """
import resource
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
import cv2
cv2.namedWindow("Display check", cv2.WINDOW_NORMAL)
cv2.waitKey(1)
cv2.destroyAllWindows()
"""
    try:
        result = subprocess.run([sys.executable, "-c", code], capture_output=True,
                                text=True, timeout=20)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("Desktop display check timed out. Use a desktop terminal "
                           "or --headless.") from exc
    if result.returncode:
        raise RuntimeError(
            "OpenCV cannot open the desktop display. Log into the attached screen "
            "as this user and run from its terminal, or pass --headless. "
            "If it also fails there, inspect the Qt/OpenCV installation.\n"
            + result.stderr[-1800:])
    print(f"Display ready: {os.environ['DISPLAY']}", flush=True)
