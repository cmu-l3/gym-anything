#!/usr/bin/env python3
"""
PyAutoGUI Command Server for Windows

This server runs in the Windows desktop session and accepts JSON commands
over TCP to execute pyautogui functions. This solves the problem that
pyautogui doesn't work via SSH on Windows because SSH sessions don't have
access to the interactive desktop.

Usage:
    Run this script from the Windows desktop session (not SSH):
    python windows_pyautogui_server.py --port 5555

    The server will listen for JSON commands and return JSON responses.

Protocol:
    - Each message is a JSON object followed by newline
    - Request: {"action": "move", "x": 100, "y": 200}
    - Response: {"success": true, "result": null} or {"success": false, "error": "..."}

Supported actions:
    - move: move mouse to x, y
    - click: click at current position or x, y
    - doubleClick: double click
    - rightClick: right click
    - drag: drag to x, y
    - scroll: scroll amount (positive=up, negative=down)
    - write: type text
    - press: press key(s)
    - hotkey: press key combination
    - screenshot: take screenshot, returns base64 encoded PNG
    - getPosition: get current mouse position
    - getScreenSize: get screen dimensions
    - ping: health check
"""

import argparse
import base64
import io
import json
import socket
import sys
import threading
import traceback
from typing import Any, Dict, Optional

try:
    import pyautogui
    pyautogui.FAILSAFE = False  # Disable fail-safe (moving to corner doesn't abort)
    pyautogui.PAUSE = 0.05  # Small pause between actions
except ImportError:
    print("ERROR: pyautogui not installed. Run: pip install pyautogui")
    sys.exit(1)

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow not installed. Run: pip install Pillow")
    sys.exit(1)


class PyAutoGUIServer:
    """TCP server that executes pyautogui commands."""

    def __init__(self, host: str = "0.0.0.0", port: int = 5555):
        self.host = host
        self.port = port
        self.socket = None
        self.running = False

    def start(self):
        """Start the server and listen for connections."""
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind((self.host, self.port))
        self.socket.listen(5)
        self.running = True

        print(f"PyAutoGUI Server listening on {self.host}:{self.port}")
        print(f"Screen size: {pyautogui.size()}")
        print("Waiting for connections...")

        while self.running:
            try:
                client, addr = self.socket.accept()
                print(f"Connection from {addr}")
                thread = threading.Thread(target=self.handle_client, args=(client, addr))
                thread.daemon = True
                thread.start()
            except socket.error as e:
                if self.running:
                    print(f"Socket error: {e}")

    def handle_client(self, client: socket.socket, addr):
        """Handle a single client connection."""
        buffer = ""
        try:
            while self.running:
                data = client.recv(4096)
                if not data:
                    break

                buffer += data.decode('utf-8')

                # Process complete JSON messages (terminated by newline)
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    if line.strip():
                        response = self.process_command(line.strip())
                        client.send((json.dumps(response) + '\n').encode('utf-8'))

        except Exception as e:
            print(f"Error handling client {addr}: {e}")
            traceback.print_exc()
        finally:
            client.close()
            print(f"Connection closed: {addr}")

    def process_command(self, command_json: str) -> Dict[str, Any]:
        """Process a JSON command and return the result."""
        try:
            cmd = json.loads(command_json)
        except json.JSONDecodeError as e:
            return {"success": False, "error": f"Invalid JSON: {e}"}

        action = cmd.get("action")
        if not action:
            return {"success": False, "error": "Missing 'action' field"}

        try:
            result = self.execute_action(action, cmd)
            return {"success": True, "result": result}
        except Exception as e:
            traceback.print_exc()
            return {"success": False, "error": str(e)}

    def execute_action(self, action: str, cmd: Dict[str, Any]) -> Any:
        """Execute a pyautogui action and return the result."""

        if action == "ping":
            return "pong"

        elif action == "getPosition":
            pos = pyautogui.position()
            return {"x": pos.x, "y": pos.y}

        elif action == "getScreenSize":
            size = pyautogui.size()
            return {"width": size.width, "height": size.height}

        elif action == "move":
            x = cmd.get("x", 0)
            y = cmd.get("y", 0)
            duration = cmd.get("duration", 0)
            pyautogui.moveTo(x, y, duration=duration)
            return None

        elif action == "click":
            x = cmd.get("x")
            y = cmd.get("y")
            button = cmd.get("button", "left")
            clicks = cmd.get("clicks", 1)
            if x is not None and y is not None:
                pyautogui.click(x, y, button=button, clicks=clicks)
            else:
                pyautogui.click(button=button, clicks=clicks)
            return None

        elif action == "doubleClick":
            x = cmd.get("x")
            y = cmd.get("y")
            if x is not None and y is not None:
                pyautogui.doubleClick(x, y)
            else:
                pyautogui.doubleClick()
            return None

        elif action == "rightClick":
            x = cmd.get("x")
            y = cmd.get("y")
            if x is not None and y is not None:
                pyautogui.rightClick(x, y)
            else:
                pyautogui.rightClick()
            return None

        elif action == "drag":
            x = cmd.get("x", 0)
            y = cmd.get("y", 0)
            duration = cmd.get("duration", 0.5)
            button = cmd.get("button", "left")
            pyautogui.drag(x, y, duration=duration, button=button)
            return None

        elif action == "dragTo":
            x = cmd.get("x", 0)
            y = cmd.get("y", 0)
            duration = cmd.get("duration", 0.5)
            button = cmd.get("button", "left")
            pyautogui.dragTo(x, y, duration=duration, button=button)
            return None

        elif action == "scroll":
            amount = cmd.get("amount", 0)
            x = cmd.get("x")
            y = cmd.get("y")
            if x is not None and y is not None:
                pyautogui.scroll(amount, x, y)
            else:
                pyautogui.scroll(amount)
            return None

        elif action == "write":
            text = cmd.get("text", "")
            interval = cmd.get("interval", 0.05)
            pyautogui.write(text, interval=interval)
            return None

        elif action == "typewrite":
            # Alias for write
            text = cmd.get("text", "")
            interval = cmd.get("interval", 0.05)
            pyautogui.typewrite(text, interval=interval)
            return None

        elif action == "press":
            keys = cmd.get("keys", cmd.get("key", ""))
            presses = cmd.get("presses", 1)
            interval = cmd.get("interval", 0.1)
            if isinstance(keys, list):
                for key in keys:
                    pyautogui.press(key, presses=presses, interval=interval)
            else:
                pyautogui.press(keys, presses=presses, interval=interval)
            return None

        elif action == "hotkey":
            keys = cmd.get("keys", [])
            if isinstance(keys, list):
                pyautogui.hotkey(*keys)
            else:
                pyautogui.hotkey(keys)
            return None

        elif action == "keyDown":
            key = cmd.get("key", "")
            pyautogui.keyDown(key)
            return None

        elif action == "keyUp":
            key = cmd.get("key", "")
            pyautogui.keyUp(key)
            return None

        elif action == "screenshot":
            # Take screenshot and return as base64 PNG
            region = cmd.get("region")  # Optional: [x, y, width, height]
            if region:
                img = pyautogui.screenshot(region=tuple(region))
            else:
                img = pyautogui.screenshot()

            # Convert to base64 PNG
            buffer = io.BytesIO()
            img.save(buffer, format='PNG')
            img_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')

            return {
                "width": img.width,
                "height": img.height,
                "format": "png",
                "data": img_base64
            }

        elif action == "locateOnScreen":
            # Find image on screen
            image_path = cmd.get("image")
            confidence = cmd.get("confidence", 0.9)
            if not image_path:
                raise ValueError("Missing 'image' parameter")
            try:
                location = pyautogui.locateOnScreen(image_path, confidence=confidence)
                if location:
                    return {"x": location.left, "y": location.top,
                            "width": location.width, "height": location.height}
                return None
            except Exception as e:
                raise ValueError(f"locateOnScreen failed: {e}")

        elif action == "pixel":
            # Get pixel color at position
            x = cmd.get("x", 0)
            y = cmd.get("y", 0)
            color = pyautogui.pixel(x, y)
            return {"r": color[0], "g": color[1], "b": color[2]}

        else:
            raise ValueError(f"Unknown action: {action}")

    def stop(self):
        """Stop the server."""
        self.running = False
        if self.socket:
            self.socket.close()


def main():
    parser = argparse.ArgumentParser(description="PyAutoGUI Command Server")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=5555, help="Port to listen on")
    args = parser.parse_args()

    server = PyAutoGUIServer(host=args.host, port=args.port)

    try:
        server.start()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.stop()


if __name__ == "__main__":
    main()
