"""
VNC Utilities for QEMU-based environments.

This module provides VNC-based screenshot capture and action injection
for QEMU VMs running inside Apptainer containers.
"""

from __future__ import annotations

import base64
import io
import os
import socket
import struct
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# Key code mappings from X11 keysyms to VNC keycodes
# Reference: https://www.x.org/releases/X11R7.7/doc/xproto/x11protocol.html#keysym_encoding
VNC_KEY_MAP = {
    # Special keys
    "Return": 0xff0d,
    "return": 0xff0d,
    "Enter": 0xff0d,
    "enter": 0xff0d,
    "Tab": 0xff09,
    "tab": 0xff09,
    "Escape": 0xff1b,
    "escape": 0xff1b,
    "esc": 0xff1b,
    "Esc": 0xff1b,
    "BackSpace": 0xff08,
    "backspace": 0xff08,
    "Delete": 0xffff,
    "delete": 0xffff,
    "insert": 0xff63,
    "Insert": 0xff63,
    "Home": 0xff50,
    "End": 0xff57,
    "Page_Up": 0xff55,
    "Page_Down": 0xff56,
    "Left": 0xff51,
    "Up": 0xff52,
    "Right": 0xff53,
    "Down": 0xff54,
    "space": 0x0020,
    "Space": 0x0020,
    # Function keys
    "F1": 0xffbe,
    "F2": 0xffbf,
    "F3": 0xffc0,
    "F4": 0xffc1,
    "F5": 0xffc2,
    "F6": 0xffc3,
    "F7": 0xffc4,
    "F8": 0xffc5,
    "F9": 0xffc6,
    "F10": 0xffc7,
    "F11": 0xffc8,
    "F12": 0xffc9,
    # Modifier keys
    "Shift_L": 0xffe1,
    "Shift_R": 0xffe2,
    "shift": 0xffe1,
    "Shift": 0xffe1,
    "Control_L": 0xffe3,
    "Control_R": 0xffe4,
    "ctrl": 0xffe3,
    "Ctrl": 0xffe3,
    "Control": 0xffe3,
    "Alt_L": 0xffe9,
    "Alt_R": 0xffea,
    "alt": 0xffe9,
    "Alt": 0xffe9,
    "Super_L": 0xffeb,
    "Super_R": 0xffec,
    "super": 0xffeb,
    "Super": 0xffeb,
    "meta": 0xffeb,
    "Meta": 0xffeb,
    "cmd": 0xffeb,
    "win": 0xffeb,
    "Win": 0xffeb,
    "Windows": 0xffeb,
    # Misc
    "Menu": 0xff67,
    "Print": 0xff61,
    "Scroll_Lock": 0xff14,
    "Pause": 0xff13,
    "Num_Lock": 0xff7f,
    "Caps_Lock": 0xffe5,
}

# Characters that require Shift key (US keyboard layout)
SHIFT_CHARS = {
    '!': '1', '@': '2', '#': '3', '$': '4', '%': '5',
    '^': '6', '&': '7', '*': '8', '(': '9', ')': '0',
    '_': '-', '+': '=', '{': '[', '}': ']', '|': '\\',
    ':': ';', '"': "'", '<': ',', '>': '.', '?': '/',
    '~': '`',
}

# Uppercase letters also need shift
for c in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ':
    SHIFT_CHARS[c] = c.lower()


def char_needs_shift(char: str) -> Tuple[bool, str]:
    """Check if a character needs Shift key and return the base key.

    Returns:
        Tuple of (needs_shift, base_key)
    """
    if char in SHIFT_CHARS:
        return True, SHIFT_CHARS[char]
    return False, char


def char_to_keysym(char: str) -> int:
    """Convert a single character to its X11 keysym."""
    if len(char) != 1:
        raise ValueError(f"Expected single character, got: {char}")
    
    # ASCII printable characters map directly
    code = ord(char)
    if 0x20 <= code <= 0x7e:
        return code
    
    # Latin-1 supplement (0x80-0xff) maps to keysym range 0x00a0-0x00ff
    if 0xa0 <= code <= 0xff:
        return code
    
    # For Unicode, use the Unicode keysym encoding (0x01000000 + codepoint)
    return 0x01000000 + code


def key_to_keysym(key: str) -> int:
    """Convert a key name or character to its X11 keysym."""
    # Check special key map first
    if key in VNC_KEY_MAP:
        return VNC_KEY_MAP[key]
    VNC_KEY_MAP_lower = {k.lower(): v for k, v in VNC_KEY_MAP.items()}
    if key.lower() in VNC_KEY_MAP_lower:
        return VNC_KEY_MAP_lower[key.lower()]
    
    # Single character
    if len(key) == 1:
        return char_to_keysym(key)
    
    # Try lowercase variant
    if key.lower() in VNC_KEY_MAP:
        return VNC_KEY_MAP[key.lower()]
    
    raise ValueError(f"Unknown key: {key}")


@dataclass
class VNCConnection:
    """Manages a VNC connection for screenshot capture and input injection."""
    
    host: str
    port: int
    password: Optional[str] = None
    
    _socket: Optional[socket.socket] = None
    _width: int = 0
    _height: int = 0
    _pixel_format: Dict[str, Any] = None
    _name: str = ""
    _lock: threading.Lock = None
    
    def __post_init__(self):
        self._lock = threading.Lock()
        self._pixel_format = {}
    
    def connect(self, timeout: float = 30.0) -> bool:
        """Establish VNC connection with handshake."""
        with self._lock:
            try:
                self._socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self._socket.settimeout(timeout)
                self._socket.connect((self.host, self.port))
                
                # Protocol version handshake
                version = self._socket.recv(12)
                if not version.startswith(b"RFB "):
                    raise ConnectionError(f"Invalid VNC protocol version: {version}")
                
                # Send our version (3.8 is widely supported)
                self._socket.send(b"RFB 003.008\n")
                
                # Security handshake
                if not self._do_security_handshake():
                    return False
                
                # Client init - request shared desktop
                self._socket.send(struct.pack("!B", 1))  # shared=1
                
                # Server init
                server_init = self._socket.recv(24)
                self._width, self._height = struct.unpack("!HH", server_init[0:4])
                
                # Parse pixel format (16 bytes)
                pf = server_init[4:20]
                self._pixel_format = {
                    "bpp": pf[0],
                    "depth": pf[1],
                    "big_endian": pf[2],
                    "true_color": pf[3],
                    "red_max": struct.unpack("!H", pf[4:6])[0],
                    "green_max": struct.unpack("!H", pf[6:8])[0],
                    "blue_max": struct.unpack("!H", pf[8:10])[0],
                    "red_shift": pf[10],
                    "green_shift": pf[11],
                    "blue_shift": pf[12],
                }
                
                # Desktop name
                name_len = struct.unpack("!I", server_init[20:24])[0]
                if name_len > 0:
                    self._name = self._socket.recv(name_len).decode("utf-8", errors="ignore")
                
                # Set pixel format to 32-bit BGRA for easier handling
                self._set_pixel_format()
                
                # Set encoding preferences
                self._set_encodings()
                
                print(f"[VNC] Connected to {self._name} ({self._width}x{self._height})")
                return True
                
            except Exception as e:
                print(f"[VNC] Connection failed: {e}")
                self.close()
                return False
    
    def _do_security_handshake(self) -> bool:
        """Handle VNC security handshake."""
        # Get security types count
        num_types = struct.unpack("!B", self._socket.recv(1))[0]
        
        if num_types == 0:
            # Connection failed - read reason
            reason_len = struct.unpack("!I", self._socket.recv(4))[0]
            reason = self._socket.recv(reason_len).decode("utf-8", errors="ignore")
            raise ConnectionError(f"VNC connection refused: {reason}")
        
        # Read available security types
        types = list(self._socket.recv(num_types))
        
        # Prefer no auth (1), then VNC auth (2)
        if 1 in types:
            # No authentication
            self._socket.send(struct.pack("!B", 1))
        elif 2 in types:
            # VNC authentication
            self._socket.send(struct.pack("!B", 2))
            if not self._vnc_auth():
                return False
        else:
            raise ConnectionError(f"No supported security type: {types}")
        
        # Check security result
        result = struct.unpack("!I", self._socket.recv(4))[0]
        if result != 0:
            # Read failure reason (RFB 3.8+)
            try:
                reason_len = struct.unpack("!I", self._socket.recv(4))[0]
                reason = self._socket.recv(reason_len).decode("utf-8", errors="ignore")
                raise ConnectionError(f"VNC authentication failed: {reason}")
            except:
                raise ConnectionError("VNC authentication failed")
        
        return True
    
    def _vnc_auth(self) -> bool:
        """Handle VNC DES authentication."""
        try:
            from Crypto.Cipher import DES
        except ImportError:
            try:
                from Cryptodome.Cipher import DES
            except ImportError:
                raise ImportError("pycryptodome is required for VNC authentication: pip install pycryptodome")
        
        # Receive 16-byte challenge
        challenge = self._socket.recv(16)
        
        if not self.password:
            raise ValueError("VNC password required but not provided")
        
        # DES encrypt challenge with password
        # VNC uses a reversed bit order for the key
        password_bytes = self.password.encode("latin-1")[:8].ljust(8, b"\x00")
        key = bytes([sum((b >> i & 1) << (7 - i) for i in range(8)) for b in password_bytes])
        
        cipher = DES.new(key, DES.MODE_ECB)
        response = cipher.encrypt(challenge[:8]) + cipher.encrypt(challenge[8:16])
        
        self._socket.send(response)
        return True
    
    def _set_pixel_format(self):
        """Request 32-bit BGRA pixel format."""
        # Message type 0 = SetPixelFormat
        msg = struct.pack("!B", 0)
        msg += b"\x00\x00\x00"  # padding
        # Pixel format: 32bpp, 24 depth, little endian, true color
        msg += struct.pack("!BBBB", 32, 24, 0, 1)
        # RGB max: 255 each
        msg += struct.pack("!HHH", 255, 255, 255)
        # RGB shifts: 16, 8, 0 (for BGR ordering)
        msg += struct.pack("!BBB", 16, 8, 0)
        msg += b"\x00\x00\x00"  # padding
        
        self._socket.send(msg)
        self._pixel_format = {
            "bpp": 32,
            "depth": 24,
            "big_endian": False,
            "true_color": True,
            "red_max": 255,
            "green_max": 255,
            "blue_max": 255,
            "red_shift": 16,
            "green_shift": 8,
            "blue_shift": 0,
        }
    
    def _set_encodings(self):
        """Set preferred encodings."""
        # Message type 2 = SetEncodings
        encodings = [
            0,    # Raw encoding (most compatible)
            -223, # DesktopSize pseudo-encoding
        ]
        msg = struct.pack("!BxH", 2, len(encodings))
        for enc in encodings:
            msg += struct.pack("!i", enc)
        self._socket.send(msg)
    
    def close(self):
        """Close the VNC connection."""
        with self._lock:
            if self._socket:
                try:
                    self._socket.close()
                except:
                    pass
                self._socket = None
    
    @property
    def is_connected(self) -> bool:
        return self._socket is not None
    
    @property
    def resolution(self) -> Tuple[int, int]:
        return (self._width, self._height)
    
    def capture_screenshot(self, save_path: Optional[Path] = None) -> Optional[bytes]:
        """Capture a screenshot from VNC and optionally save as PNG."""
        with self._lock:
            if not self._socket:
                return None
            
            try:
                # Request framebuffer update
                # Message type 3 = FramebufferUpdateRequest
                # incremental=0 (full update), x=0, y=0, width, height
                msg = struct.pack("!BBHHHH", 3, 0, 0, 0, self._width, self._height)
                self._socket.send(msg)
                
                # Read framebuffer update response
                self._socket.settimeout(10.0)
                
                while True:
                    msg_type = struct.unpack("!B", self._socket.recv(1))[0]
                    
                    if msg_type == 0:  # FramebufferUpdate
                        break
                    elif msg_type == 1:  # SetColorMapEntries
                        self._handle_colormap()
                    elif msg_type == 2:  # Bell
                        pass  # Ignore bell
                    elif msg_type == 3:  # ServerCutText
                        self._handle_cut_text()
                    else:
                        print(f"[VNC] Unknown message type: {msg_type}")
                        return None
                
                # Read number of rectangles
                self._socket.recv(1)  # padding
                num_rects = struct.unpack("!H", self._socket.recv(2))[0]
                
                # Initialize framebuffer
                pixels = bytearray(self._width * self._height * 4)
                
                for _ in range(num_rects):
                    # Rectangle header
                    x, y, w, h, encoding = struct.unpack("!HHHHI", self._socket.recv(12))
                    
                    if encoding == 0:  # Raw
                        # Read raw pixel data
                        bytes_per_pixel = self._pixel_format["bpp"] // 8
                        data_size = w * h * bytes_per_pixel
                        data = b""
                        while len(data) < data_size:
                            chunk = self._socket.recv(data_size - len(data))
                            if not chunk:
                                raise ConnectionError("Connection closed during read")
                            data += chunk
                        
                        # Copy to framebuffer
                        for row in range(h):
                            src_offset = row * w * bytes_per_pixel
                            dst_offset = ((y + row) * self._width + x) * 4
                            for col in range(w):
                                src_idx = src_offset + col * bytes_per_pixel
                                dst_idx = dst_offset + col * 4
                                if dst_idx + 4 <= len(pixels):
                                    pixels[dst_idx:dst_idx+4] = data[src_idx:src_idx+4]
                    
                    elif encoding == -223:  # DesktopSize
                        self._width = w
                        self._height = h
                        pixels = bytearray(w * h * 4)
                
                # Convert to PNG
                try:
                    from PIL import Image
                    
                    # Create image from BGRA data
                    img = Image.frombytes("RGBA", (self._width, self._height), bytes(pixels), "raw", "BGRA")
                    img = img.convert("RGB")
                    
                    if save_path:
                        save_path = Path(save_path)
                        save_path.parent.mkdir(parents=True, exist_ok=True)
                        img.save(save_path, "PNG")
                    
                    # Return PNG bytes
                    buf = io.BytesIO()
                    img.save(buf, "PNG")
                    return buf.getvalue()
                    
                except ImportError:
                    print("[VNC] PIL not available for image conversion")
                    return bytes(pixels)
                
            except socket.timeout:
                print("[VNC] Screenshot timeout")
                return None
            except Exception as e:
                print(f"[VNC] Screenshot error: {e}")
                return None
    
    def _handle_colormap(self):
        """Handle SetColorMapEntries message."""
        self._socket.recv(1)  # padding
        first_color = struct.unpack("!H", self._socket.recv(2))[0]
        num_colors = struct.unpack("!H", self._socket.recv(2))[0]
        # Read and discard color entries
        self._socket.recv(num_colors * 6)
    
    def _handle_cut_text(self):
        """Handle ServerCutText message."""
        self._socket.recv(3)  # padding
        length = struct.unpack("!I", self._socket.recv(4))[0]
        self._socket.recv(length)  # discard text
    
    def send_key(self, key: str, down: bool = True):
        """Send a key press or release event."""
        with self._lock:
            if not self._socket:
                return
            
            keysym = key_to_keysym(key)
            # Message type 4 = KeyEvent
            # down_flag (1=pressed), padding (2 bytes), keysym (4 bytes)
            msg = struct.pack("!BBxxI", 4, 1 if down else 0, keysym)
            self._socket.send(msg)
    
    def send_key_combo(self, keys: List[str], delay: float = 0.01):
        """Send a key combination (e.g., Ctrl+C)."""
        # Press all keys
        for key in keys:
            self.send_key(key, down=True)
            time.sleep(delay)
        
        # Release in reverse order
        for key in reversed(keys):
            self.send_key(key, down=False)
            time.sleep(delay)
    
    def type_text(self, text: str, delay: float = 0.02):
        """Type a string of text with proper shift handling."""
        for char in text:
            needs_shift, base_key = char_needs_shift(char)

            if needs_shift:
                # Press Shift, then key, then release both
                self.send_key("Shift_L", down=True)
                time.sleep(delay / 4)

            self.send_key(base_key, down=True)
            time.sleep(delay / 2)
            self.send_key(base_key, down=False)
            time.sleep(delay / 4)

            if needs_shift:
                self.send_key("Shift_L", down=False)
                time.sleep(delay / 4)
    
    def send_mouse_move(self, x: int, y: int):
        """Move the mouse pointer."""
        with self._lock:
            if not self._socket:
                return
            
            # Clamp coordinates
            x = max(0, min(x, self._width - 1))
            y = max(0, min(y, self._height - 1))
            
            # Message type 5 = PointerEvent
            # button_mask (1 byte), x (2 bytes), y (2 bytes)
            msg = struct.pack("!BBHH", 5, 0, x, y)
            self._socket.send(msg)
    
    def send_mouse_click(self, x: int, y: int, button: int = 1, double: bool = False):
        """Send a mouse click at the specified position.
        
        Args:
            x, y: Coordinates
            button: 1=left, 2=middle, 3=right
            double: If True, send double-click
        """
        with self._lock:
            if not self._socket:
                return
            
            # Clamp coordinates
            x = max(0, min(x, self._width - 1))
            y = max(0, min(y, self._height - 1))
            
            button_mask = 1 << (button - 1)
            
            clicks = 2 if double else 1
            for _ in range(clicks):
                # Move to position
                msg = struct.pack("!BBHH", 5, 0, x, y)
                self._socket.send(msg)
                time.sleep(0.01)
                
                # Button down
                msg = struct.pack("!BBHH", 5, button_mask, x, y)
                self._socket.send(msg)
                time.sleep(0.05)
                
                # Button up
                msg = struct.pack("!BBHH", 5, 0, x, y)
                self._socket.send(msg)
                time.sleep(0.05)
    
    def send_mouse_drag(self, x1: int, y1: int, x2: int, y2: int, button: int = 1, steps: int = 20):
        """Send a mouse drag from (x1, y1) to (x2, y2)."""
        with self._lock:
            if not self._socket:
                return
            
            button_mask = 1 << (button - 1)
            
            # Move to start position
            msg = struct.pack("!BBHH", 5, 0, x1, y1)
            self._socket.send(msg)
            time.sleep(0.05)
            
            # Button down at start
            msg = struct.pack("!BBHH", 5, button_mask, x1, y1)
            self._socket.send(msg)
            time.sleep(0.05)
            
            # Interpolate movement
            for i in range(1, steps + 1):
                t = i / steps
                x = int(x1 + (x2 - x1) * t)
                y = int(y1 + (y2 - y1) * t)
                msg = struct.pack("!BBHH", 5, button_mask, x, y)
                self._socket.send(msg)
                time.sleep(0.02)
            
            # Button up at end
            msg = struct.pack("!BBHH", 5, 0, x2, y2)
            self._socket.send(msg)
    
    def send_scroll(self, x: int, y: int, delta: int):
        """Send mouse scroll at position.
        
        Args:
            x, y: Coordinates
            delta: Positive for scroll up, negative for scroll down
        """
        with self._lock:
            if not self._socket:
                return
            
            # Move to position first
            msg = struct.pack("!BBHH", 5, 0, x, y)
            self._socket.send(msg)
            time.sleep(0.01)
            
            # Button 4 = scroll up, button 5 = scroll down
            button = 4 if delta > 0 else 5
            button_mask = 1 << (button - 1)
            
            for _ in range(abs(delta)):
                # Click scroll button
                msg = struct.pack("!BBHH", 5, button_mask, x, y)
                self._socket.send(msg)
                time.sleep(0.02)
                msg = struct.pack("!BBHH", 5, 0, x, y)
                self._socket.send(msg)
                time.sleep(0.02)


class VNCConnectionPool:
    """Manages VNC connections with reconnection support."""
    
    def __init__(self, host: str, port: int, password: Optional[str] = None):
        self.host = host
        self.port = port
        self.password = password
        self._connection: Optional[VNCConnection] = None
        self._lock = threading.Lock()
    
    def get_connection(self, retry_count: int = 3, retry_delay: float = 2.0) -> Optional[VNCConnection]:
        """Get a VNC connection, reconnecting if necessary."""
        with self._lock:
            if self._connection and self._connection.is_connected:
                return self._connection
            
            for attempt in range(retry_count):
                self._connection = VNCConnection(
                    host=self.host,
                    port=self.port,
                    password=self.password
                )
                
                if self._connection.connect():
                    return self._connection
                
                if attempt < retry_count - 1:
                    print(f"[VNCPool] Retry {attempt + 1}/{retry_count} in {retry_delay}s...")
                    time.sleep(retry_delay)
            
            return None
    
    def close(self):
        """Close the pooled connection."""
        with self._lock:
            if self._connection:
                self._connection.close()
                self._connection = None


