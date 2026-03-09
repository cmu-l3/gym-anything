#!/usr/bin/env python3
"""
PyAutoGUI Client for Windows

This client connects to the PyAutoGUI server running in the Windows desktop
session and sends commands to control the mouse/keyboard and take screenshots.

Protocol (matching pyautogui_server.py in Windows VM):
- Commands use {"type": "...", ...} format
- Responses use {"status": "ok", ...} or {"status": "error", "message": "..."}

Supported commands:
- {"action": "ping"} -> {"status": "ok", "message": "pong"}
- {"action": "move", "x": 100, "y": 200}
- {"action": "click", "x": 100, "y": 200, "button": "left", "clicks": 1}
- {"action": "write", "text": "hello", "interval": 0.0}
- {"action": "hotkey", "keys": ["ctrl", "s"]}
- {"action": "scroll", "amount": 3, "x": null, "y": null}
- {"action": "drag", "x": 100, "y": 50, "duration": 0.5, "button": "left"}
- {"action": "screenshot"} -> {"status": "ok", "width": 1280, "height": 720, "image": "<base64>"}

Usage:
    from windows_pyautogui_client import PyAutoGUIClient

    client = PyAutoGUIClient(host="localhost", port=5555)
    client.connect()

    # Move mouse
    client.move(100, 200)

    # Click
    client.click(500, 300)

    # Type text
    client.write("Hello World")

    # Take screenshot
    screenshot = client.screenshot()  # Returns PIL Image

    client.close()
"""

import base64
import io
import json
import socket
from typing import Any, Dict, List, Optional, Tuple, Union

try:
    from PIL import Image
except ImportError:
    Image = None


class PyAutoGUIClientError(Exception):
    """Exception raised when a PyAutoGUI command fails."""
    pass


class PyAutoGUIClient:
    """Client for communicating with the PyAutoGUI server."""

    def __init__(self, host: str = "localhost", port: int = 5555, timeout: float = 30.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.socket: Optional[socket.socket] = None
        self._buffer = ""

    def connect(self) -> bool:
        """Connect to the PyAutoGUI server."""
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(self.timeout)
            self.socket.connect((self.host, self.port))
            return True
        except socket.error as e:
            self.socket = None
            raise PyAutoGUIClientError(f"Failed to connect to {self.host}:{self.port}: {e}")

    def close(self):
        """Close the connection."""
        if self.socket:
            try:
                self.socket.close()
            except:
                pass
            self.socket = None

    def is_connected(self) -> bool:
        """Check if connected to the server."""
        return self.socket is not None

    def _send_command(self, cmd: Dict[str, Any]) -> Dict[str, Any]:
        """Send a command to the server and return the response."""
        if not self.socket:
            raise PyAutoGUIClientError("Not connected to server")

        try:
            # Send command
            message = json.dumps(cmd) + '\n'
            self.socket.sendall(message.encode('utf-8'))

            # Receive response (may be large for screenshots)
            while '\n' not in self._buffer:
                data = self.socket.recv(1024 * 1024)  # 1MB buffer for screenshots
                if not data:
                    raise PyAutoGUIClientError("Connection closed by server")
                self._buffer += data.decode('utf-8')

            line, self._buffer = self._buffer.split('\n', 1)
            response = json.loads(line)

            # Server uses "success": true/false format with "result" or "error"
            if response.get("success") == False:
                raise PyAutoGUIClientError(response.get("error", "Unknown error"))

            return response

        except socket.timeout:
            raise PyAutoGUIClientError("Request timed out")
        except json.JSONDecodeError as e:
            raise PyAutoGUIClientError(f"Invalid response from server: {e}")

    # ========== Basic Commands ==========

    def ping(self) -> bool:
        """Check if the server is responsive."""
        result = self._send_command({"action": "ping"})
        return result.get("success") == True and result.get("result") == "pong"

    def get_position(self) -> Tuple[int, int]:
        """Get current mouse position.
        Note: Not directly supported by server, returns (0, 0).
        """
        # Server doesn't support getPosition, return dummy value
        return (0, 0)

    def get_screen_size(self) -> Tuple[int, int]:
        """Get screen dimensions by taking a screenshot."""
        # Server doesn't have getScreenSize, but screenshot returns dimensions
        result = self._send_command({"action": "screenshot"})
        screenshot_data = result.get("result", {})
        return (screenshot_data.get("width", 1280), screenshot_data.get("height", 720))

    # ========== Mouse Commands ==========

    def move(self, x: int, y: int, duration: float = 0) -> None:
        """Move mouse to position."""
        self._send_command({"action": "move", "x": x, "y": y})

    def click(self, x: Optional[int] = None, y: Optional[int] = None,
              button: str = "left", clicks: int = 1) -> None:
        """Click at position (or current position if x/y not specified)."""
        cmd = {"action": "click", "button": button, "clicks": clicks}
        if x is not None:
            cmd["x"] = x
        if y is not None:
            cmd["y"] = y
        self._send_command(cmd)

    def double_click(self, x: Optional[int] = None, y: Optional[int] = None) -> None:
        """Double click at position."""
        cmd = {"action": "click", "clicks": 2}
        if x is not None:
            cmd["x"] = x
        if y is not None:
            cmd["y"] = y
        self._send_command(cmd)

    def right_click(self, x: Optional[int] = None, y: Optional[int] = None) -> None:
        """Right click at position."""
        cmd = {"action": "click", "button": "right"}
        if x is not None:
            cmd["x"] = x
        if y is not None:
            cmd["y"] = y
        self._send_command(cmd)

    def drag(self, x: int, y: int, duration: float = 0.5, button: str = "left") -> None:
        """Drag mouse by offset."""
        self._send_command({"action": "drag", "x": x, "y": y,
                           "duration": duration, "button": button})

    def drag_to(self, x: int, y: int, duration: float = 0.5, button: str = "left") -> None:
        """Drag mouse to absolute position."""
        # First move to start, then drag
        self._send_command({"action": "drag", "x": x, "y": y,
                           "duration": duration, "button": button})

    def scroll(self, amount: int, x: Optional[int] = None, y: Optional[int] = None) -> None:
        """Scroll mouse wheel. Positive = up, negative = down."""
        cmd = {"action": "scroll", "amount": amount}
        if x is not None:
            cmd["x"] = x
        if y is not None:
            cmd["y"] = y
        self._send_command(cmd)

    # ========== Keyboard Commands ==========

    def write(self, text: str, interval: float = 0.05) -> None:
        """Type text character by character."""
        self._send_command({"action": "write", "text": text, "interval": interval})

    def typewrite(self, text: str, interval: float = 0.05) -> None:
        """Alias for write()."""
        self.write(text, interval)

    def press(self, key: Union[str, List[str]], presses: int = 1, interval: float = 0.1) -> None:
        """Press a key or list of keys."""
        if isinstance(key, list):
            # Multiple keys = hotkey
            self._send_command({"action": "hotkey", "keys": key})
        else:
            # Single key - wrap in list
            self._send_command({"action": "hotkey", "keys": [key]})

    def hotkey(self, *keys: str) -> None:
        """Press a key combination (e.g., hotkey('ctrl', 'c'))."""
        self._send_command({"action": "hotkey", "keys": list(keys)})

    def key_down(self, key: str) -> None:
        """Hold down a key. Note: Server may not fully support this."""
        # Server doesn't have keyDown, use press as workaround
        self._send_command({"action": "hotkey", "keys": [key]})

    def key_up(self, key: str) -> None:
        """Release a key. Note: Server may not fully support this."""
        # Server doesn't have keyUp, this is a no-op
        pass

    # ========== Screenshot Commands ==========

    def screenshot(self, region: Optional[Tuple[int, int, int, int]] = None) -> Optional["Image.Image"]:
        """
        Take a screenshot.

        Args:
            region: Optional (x, y, width, height) tuple for partial screenshot

        Returns:
            PIL Image object, or None if PIL is not available
        """
        cmd = {"action": "screenshot"}
        # Note: Server doesn't support region parameter

        result = self._send_command(cmd)

        if Image is None:
            # Return raw data if PIL not available
            return result

        # Server returns: {"success": true, "result": {"width": W, "height": H, "format": "png", "data": "..."}}
        screenshot_data = result.get("result", {})
        img_data = base64.b64decode(screenshot_data.get("data", ""))
        img = Image.open(io.BytesIO(img_data))
        return img

    def screenshot_bytes(self, region: Optional[Tuple[int, int, int, int]] = None) -> bytes:
        """Take a screenshot and return raw PNG bytes."""
        cmd = {"action": "screenshot"}

        result = self._send_command(cmd)
        screenshot_data = result.get("result", {})
        return base64.b64decode(screenshot_data.get("data", ""))

    def screenshot_base64(self, region: Optional[Tuple[int, int, int, int]] = None) -> str:
        """Take a screenshot and return base64-encoded PNG."""
        cmd = {"action": "screenshot"}

        result = self._send_command(cmd)
        screenshot_data = result.get("result", {})
        return screenshot_data.get("data", "")

    # ========== Utility Commands ==========

    def get_pixel(self, x: int, y: int) -> Tuple[int, int, int]:
        """Get pixel color at position. Returns (R, G, B).
        Note: Not supported by server, takes screenshot and extracts pixel.
        """
        # Get full screenshot and extract pixel
        img = self.screenshot()
        if img and hasattr(img, 'getpixel'):
            pixel = img.getpixel((x, y))
            return pixel[:3] if len(pixel) >= 3 else (0, 0, 0)
        return (0, 0, 0)

    def locate_on_screen(self, image_path: str, confidence: float = 0.9) -> Optional[Dict[str, int]]:
        """
        Find an image on screen.
        Note: Not supported by server.

        Returns:
            None (not implemented)
        """
        # Server doesn't support this
        return None


# Convenience function for quick testing
def test_connection(host: str = "localhost", port: int = 5555) -> bool:
    """Quick test to check if server is running."""
    try:
        client = PyAutoGUIClient(host=host, port=port, timeout=5.0)
        client.connect()
        result = client.ping()
        client.close()
        return result
    except Exception as e:
        print(f"Connection test failed: {e}")
        return False


if __name__ == "__main__":
    # Simple test
    import sys

    host = sys.argv[1] if len(sys.argv) > 1 else "localhost"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 5555

    print(f"Testing connection to {host}:{port}...")

    if test_connection(host, port):
        print("SUCCESS: Server is running and responsive")

        client = PyAutoGUIClient(host=host, port=port)
        client.connect()

        print(f"Screen size: {client.get_screen_size()}")
        print(f"Mouse position: {client.get_position()}")

        # Test mouse movement
        print("Moving mouse to (100, 100)...")
        client.move(100, 100)
        print(f"New position: {client.get_position()}")

        # Test screenshot
        print("Taking screenshot...")
        img = client.screenshot()
        if img:
            print(f"Screenshot size: {img.size}")
            img.save("test_screenshot.png")
            print("Saved to test_screenshot.png")

        client.close()
    else:
        print("FAILED: Cannot connect to server")
        sys.exit(1)
