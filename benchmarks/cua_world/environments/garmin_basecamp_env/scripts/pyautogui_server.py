#!/usr/bin/env python3
"""
PyAutoGUI TCP Server — listens on 127.0.0.1:5555 for JSON commands.
Must run in the interactive desktop session (Session 1) so GUI actions work.

Supported commands (JSON objects):
  {"action": "click",       "x": N, "y": N}
  {"action": "rightClick",  "x": N, "y": N}
  {"action": "doubleClick", "x": N, "y": N}
  {"action": "moveTo",      "x": N, "y": N}
  {"action": "typewrite",   "text": "..."}
  {"action": "hotkey",      "keys": ["ctrl","i"]}
  {"action": "press",       "key": "enter"}
  {"action": "keyDown",     "key": "shift"}
  {"action": "keyUp",       "key": "shift"}
  {"action": "scroll",      "clicks": N, "x": N, "y": N}
  {"action": "screenshot",  "path": "C:\\tmp\\s.png"}
  {"action": "sleep",       "seconds": N}
  {"action": "getPos"}
  {"action": "ping"}
"""
import socket
import json
import time
import threading
import sys

try:
    import pyautogui
    pyautogui.FAILSAFE = False
    pyautogui.PAUSE = 0.05
    HAS_PYAUTOGUI = True
except ImportError:
    HAS_PYAUTOGUI = False
    print("WARNING: pyautogui not available", file=sys.stderr)


HOST = "127.0.0.1"
PORT = 5555


def handle(cmd):
    if not HAS_PYAUTOGUI:
        return {"status": "error", "error": "pyautogui not installed"}

    action = cmd.get("action", "")
    try:
        if action == "ping":
            return {"status": "ok", "msg": "pong"}
        elif action == "click":
            pyautogui.click(cmd["x"], cmd["y"])
        elif action == "rightClick":
            pyautogui.rightClick(cmd["x"], cmd["y"])
        elif action == "doubleClick":
            pyautogui.doubleClick(cmd["x"], cmd["y"])
        elif action == "moveTo":
            pyautogui.moveTo(cmd["x"], cmd["y"])
        elif action == "typewrite":
            text = cmd["text"]
            interval = cmd.get("interval", 0.05)
            # Use pyautogui.write for printable ASCII, typewrite for special
            pyautogui.typewrite(text, interval=interval)
        elif action == "hotkey":
            pyautogui.hotkey(*cmd["keys"])
        elif action == "press":
            pyautogui.press(cmd["key"])
        elif action == "keyDown":
            pyautogui.keyDown(cmd["key"])
        elif action == "keyUp":
            pyautogui.keyUp(cmd["key"])
        elif action == "scroll":
            x = cmd.get("x")
            y = cmd.get("y")
            if x is not None and y is not None:
                pyautogui.scroll(cmd.get("clicks", 3), x=x, y=y)
            else:
                pyautogui.scroll(cmd.get("clicks", 3))
        elif action == "screenshot":
            path = cmd.get("path", "C:\\temp\\screenshot.png")
            img = pyautogui.screenshot()
            img.save(path)
            return {"status": "ok", "path": path}
        elif action == "sleep":
            time.sleep(cmd.get("seconds", 1))
        elif action == "getPos":
            x, y = pyautogui.position()
            return {"status": "ok", "x": x, "y": y}
        else:
            return {"status": "error", "error": f"unknown action: {action}"}
        return {"status": "ok"}
    except Exception as e:
        return {"status": "error", "error": str(e)}


def client_thread(conn):
    try:
        data = b""
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
            if len(data) > 0:
                # Try to parse, keep receiving if incomplete
                try:
                    cmd = json.loads(data.decode("utf-8"))
                    result = handle(cmd)
                    conn.sendall(json.dumps(result).encode("utf-8"))
                    break
                except json.JSONDecodeError:
                    continue
    except Exception as e:
        try:
            conn.sendall(json.dumps({"status": "error", "error": str(e)}).encode("utf-8"))
        except Exception:
            pass
    finally:
        conn.close()


def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(32)
    print(f"PyAutoGUI server listening on {HOST}:{PORT}", flush=True)

    while True:
        try:
            conn, addr = server.accept()
            t = threading.Thread(target=client_thread, args=(conn,), daemon=True)
            t.start()
        except Exception as e:
            print(f"Accept error: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
