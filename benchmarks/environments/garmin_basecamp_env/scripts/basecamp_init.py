#!/usr/bin/env python3
"""
basecamp_init.py  –  runs in Session 1 (interactive desktop) via schtasks /IT
Launches Garmin BaseCamp, imports fells_loop.gpx, closes BaseCamp, and
backs up AllData.gdb so task setups can restore it.

Writes C:\GarminTools\setup_done.flag when complete.
Writes C:\GarminTools\setup_error.txt on failure.
"""
import subprocess
import time
import sys
import os
import shutil
import glob

# Resolve pyautogui
try:
    import pyautogui
    pyautogui.FAILSAFE = False
    pyautogui.PAUSE = 0.1
except ImportError:
    print("ERROR: pyautogui not found", file=sys.stderr)
    with open("C:\\GarminTools\\setup_error.txt", "w") as f:
        f.write("pyautogui not installed")
    sys.exit(1)

MARKER_DONE  = r"C:\GarminTools\setup_done.flag"
MARKER_ERROR = r"C:\GarminTools\setup_error.txt"
BACKUP_DIR   = r"C:\GarminTools\BaseCampBackup"
GPX_FILE     = r"C:\workspace\data\fells_loop.gpx"

def find_basecamp():
    candidates = [
        r"C:\Program Files (x86)\Garmin\BaseCamp\BaseCamp.exe",
        r"C:\Program Files\Garmin\BaseCamp\BaseCamp.exe",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    # Broad search
    for pat in [r"C:\Program Files*\Garmin\BaseCamp\BaseCamp.exe"]:
        found = glob.glob(pat)
        if found:
            return found[0]
    return None

def find_alldata_gdb():
    """Find the AllData.gdb file BaseCamp uses."""
    base = os.path.expandvars(r"%APPDATA%\Garmin\BaseCamp\Database")
    if os.path.exists(base):
        for root, dirs, files in os.walk(base):
            for f in files:
                if f.lower() == "alldata.gdb":
                    return os.path.join(root, f)
    return None

def wait_for_window(title_fragment, timeout=60):
    """Wait until a window containing title_fragment appears."""
    try:
        import pygetwindow as gw
    except ImportError:
        # Fallback: wait fixed time
        time.sleep(15)
        return True
    start = time.time()
    while time.time() - start < timeout:
        wins = gw.getAllTitles()
        if any(title_fragment.lower() in w.lower() for w in wins):
            return True
        time.sleep(1)
    return False

def bring_to_front(title_fragment):
    try:
        import pygetwindow as gw
        wins = [w for w in gw.getAllWindows()
                if title_fragment.lower() in w.title.lower()]
        if wins:
            wins[0].activate()
            time.sleep(0.5)
    except Exception:
        pass

def main():
    os.makedirs("C:\\GarminTools", exist_ok=True)

    # ── Find BaseCamp ──────────────────────────────────────────────
    bc_exe = find_basecamp()
    if not bc_exe:
        msg = "BaseCamp.exe not found"
        print(f"ERROR: {msg}")
        with open(MARKER_ERROR, "w") as f:
            f.write(msg)
        sys.exit(1)
    print(f"Found BaseCamp: {bc_exe}")

    # ── Launch BaseCamp ────────────────────────────────────────────
    print("Launching BaseCamp...")
    subprocess.Popen([bc_exe])
    time.sleep(3)

    # ── Wait for BaseCamp window ───────────────────────────────────
    print("Waiting for BaseCamp window...")
    appeared = wait_for_window("BaseCamp", timeout=60)
    if not appeared:
        print("WARNING: BaseCamp window not detected – proceeding anyway")
    time.sleep(5)  # Extra stabilization
    bring_to_front("BaseCamp")
    time.sleep(1)

    # ── Dismiss any first-run dialogs ─────────────────────────────
    # Press Escape a few times to dismiss dialogs/tips
    for _ in range(3):
        pyautogui.press("escape")
        time.sleep(0.5)
    # Close any "no device" notification (Enter or Escape)
    pyautogui.press("enter")
    time.sleep(0.5)

    # ── Import fells_loop.gpx ─────────────────────────────────────
    if not os.path.exists(GPX_FILE):
        print(f"WARNING: GPX file not found: {GPX_FILE}")
        msg = f"GPX file not found: {GPX_FILE}"
        with open(MARKER_ERROR, "w") as f:
            f.write(msg)
    else:
        print(f"Importing: {GPX_FILE}")
        bring_to_front("BaseCamp")
        time.sleep(0.5)

        # Ctrl+I opens the Import dialog in BaseCamp
        pyautogui.hotkey("ctrl", "i")
        time.sleep(3)  # Wait for file dialog to open

        # In the Windows file dialog, type the full path into the filename field
        # Press Ctrl+A to select all text in filename field, then type the path
        pyautogui.hotkey("ctrl", "a")
        time.sleep(0.3)
        # Type path (use pyautogui.write for special chars)
        for ch in GPX_FILE:
            pyautogui.typewrite(ch, interval=0.02)
        time.sleep(0.5)
        pyautogui.press("enter")
        time.sleep(5)  # Wait for import to process

        # Dismiss any import success dialog
        pyautogui.press("enter")
        time.sleep(1)
        pyautogui.press("escape")
        time.sleep(1)

        print("Import command sent. Waiting for BaseCamp to process...")
        time.sleep(5)

    # ── Close BaseCamp (saves AllData.gdb automatically) ──────────
    print("Closing BaseCamp...")
    bring_to_front("BaseCamp")
    time.sleep(0.5)
    pyautogui.hotkey("alt", "f4")
    time.sleep(2)
    # If a "save" dialog appears, confirm
    pyautogui.press("enter")
    time.sleep(3)

    # Force-kill if still running
    subprocess.run(["taskkill", "/F", "/IM", "BaseCamp.exe"],
                   capture_output=True)
    time.sleep(2)

    # ── Backup AllData.gdb ────────────────────────────────────────
    gdb_path = find_alldata_gdb()
    if gdb_path:
        print(f"Found AllData.gdb: {gdb_path}")
        os.makedirs(BACKUP_DIR, exist_ok=True)
        # Backup the entire Database folder
        db_folder = os.path.dirname(gdb_path)
        backup_dest = os.path.join(BACKUP_DIR, "Database")
        if os.path.exists(backup_dest):
            shutil.rmtree(backup_dest)
        shutil.copytree(db_folder, backup_dest)
        print(f"Backed up database to: {backup_dest}")
        # Also backup the version subfolder path for easy restore
        version = os.path.basename(db_folder)
        with open(os.path.join(BACKUP_DIR, "version.txt"), "w") as f:
            f.write(version)
    else:
        print("WARNING: AllData.gdb not found – BaseCamp may not have saved data")

    # ── Write success marker ───────────────────────────────────────
    with open(MARKER_DONE, "w") as f:
        f.write("done")
    print("Setup complete. Marker written.")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        err = traceback.format_exc()
        print(f"FATAL ERROR:\n{err}", file=sys.stderr)
        with open(MARKER_ERROR, "w") as f:
            f.write(err)
        sys.exit(1)
