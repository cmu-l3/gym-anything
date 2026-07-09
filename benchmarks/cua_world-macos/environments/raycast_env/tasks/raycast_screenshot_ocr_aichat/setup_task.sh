#!/bin/bash
# Setup: raycast_screenshot_ocr_aichat
# Renders 5 real order-confirmation screenshots with similar layouts.
# One has "Arrives Tuesday" + UPS tracking. Distractors include one with
# a visible shipping address and one with a visible card last-4.

set -euo pipefail
echo "=== Setup: raycast_screenshot_ocr_aichat ==="

DESKTOP="/Users/lume/Desktop"
PIC_SCREENSHOTS="/Users/lume/Pictures/Screenshots"
mkdir -p "$DESKTOP" "$PIC_SCREENSHOTS"

# --- 1. Ensure Raycast + dialogs ---
if ! pgrep -x "Raycast" > /dev/null 2>&1; then
    open -a "Raycast" 2>/dev/null || true
    for i in $(seq 1 15); do
        if pgrep -x "Raycast" > /dev/null 2>&1; then break; fi
        sleep 2
    done
fi
sleep 3
for _i in $(seq 1 4); do
    osascript << 'APPLEOF' 2>/dev/null || true
tell application "System Events"
    try
        repeat with proc in (every application process whose frontmost is true)
            tell proc
                if exists button "Allow" of front window then click button "Allow" of front window
                if exists button "OK" of front window then click button "OK" of front window
            end tell
        end repeat
    end try
end tell
APPLEOF
    sleep 1
done

rm -f "$DESKTOP"/screenshot_order_*.png "$PIC_SCREENSHOTS"/screenshot_order_*.png 2>/dev/null || true

python3 << 'PYEOF'
from pathlib import Path
DESKTOP = Path("/Users/lume/Desktop")
PIC = Path("/Users/lume/Pictures/Screenshots")
PIC.mkdir(parents=True, exist_ok=True)

SHOTS = [
    {
        "path": DESKTOP / "screenshot_order_amazon.png",
        "title": "Amazon.com — Order Confirmation",
        "lines": [
            "Hello, your order has been shipped.",
            "Order #112-4421-8849221",
            "Carrier: USPS Priority Mail",
            "Tracking: 9405-5111-2345-6789",
            "Expected delivery: Thursday, April 24",
            "Items: 2x Apple AirTag (4-pack)",
        ],
    },
    {
        "path": DESKTOP / "screenshot_order_target.png",
        "title": "Target — Order Update",
        "lines": [
            "Your Target order is on the way.",
            "Order #100079840221",
            "Carrier: FedEx Ground",
            "Tracking: TBA-3490-0911-43",
            "Expected delivery: Wednesday",
            "Items: bedside table lamp, sheet set",
        ],
    },
    {
        "path": PIC / "screenshot_order_bhphoto_TARGET.png",
        "title": "B&H Photo Video — Shipment Notification",
        "lines": [
            "Your order has shipped via UPS.",
            "Order #87740033-BHP",
            "Carrier: UPS Ground",
            "Tracking: 1Z-9X4-2284-7AB",
            "Arrives Tuesday",
            "Items: Sony A7C II body, 35mm f/1.8 lens",
        ],
    },
    {
        "path": PIC / "screenshot_order_rei_address.png",
        "title": "REI Co-op — Order Confirmation",
        "lines": [
            "Hi Lume, your REI order is confirmed.",
            "Order #REI-0094-22014",
            "Ship to: Lume Household",
            "2240 SE Yamhill St",
            "Portland, OR 97214",
            "Items: Osprey Atmos 65 backpack",
        ],
    },
    {
        "path": DESKTOP / "screenshot_order_newegg_card.png",
        "title": "Newegg — Payment Confirmation",
        "lines": [
            "Thank you for your order #2026-NE-771",
            "Total charged: $189.97",
            "Paid with: Discover card ending in 8821",
            "Carrier: Will ship via OnTrac",
            "Items: Logitech MX Master 3S mouse",
        ],
    },
]

try:
    from AppKit import (NSImage, NSColor, NSFont, NSBitmapImageRep,
                        NSPNGFileType, NSRectFill, NSAttributedString,
                        NSMakeRect, NSMakeSize)
    for spec in SHOTS:
        W, H = 720, 360
        img = NSImage.alloc().initWithSize_(NSMakeSize(W, H))
        img.lockFocus()
        NSColor.whiteColor().setFill()
        NSRectFill(NSMakeRect(0, 0, W, H))
        NSColor.colorWithCalibratedRed_green_blue_alpha_(0.94, 0.94, 0.96, 1.0).setFill()
        NSRectFill(NSMakeRect(0, H - 40, W, 40))
        title_font = NSFont.boldSystemFontOfSize_(15)
        title_attrs = {"NSFont": title_font, "NSColor": NSColor.blackColor()}
        nsa_title = NSAttributedString.alloc().initWithString_attributes_(spec["title"], title_attrs)
        nsa_title.drawInRect_(NSMakeRect(16, H - 32, W - 32, 26))
        body_font = NSFont.fontWithName_size_("Menlo", 13) or NSFont.systemFontOfSize_(13)
        body_attrs = {"NSFont": body_font, "NSColor": NSColor.blackColor()}
        body_text = "\n".join(spec["lines"])
        nsa_body = NSAttributedString.alloc().initWithString_attributes_(body_text, body_attrs)
        nsa_body.drawInRect_(NSMakeRect(20, 20, W - 40, H - 60))
        rep = NSBitmapImageRep.alloc().initWithFocusedViewRect_(NSMakeRect(0, 0, W, H))
        img.unlockFocus()
        png = rep.representationUsingType_properties_(NSPNGFileType, None)
        spec["path"].parent.mkdir(parents=True, exist_ok=True)
        png.writeToFile_atomically_(str(spec["path"]), True)
        print(f"WROTE {spec['path']}")
except Exception as exc:
    import sys, struct, zlib
    print(f"PyObjC render failed: {exc}", file=sys.stderr)
    def make_png(w, h, color=(255,255,255)):
        sig = b"\x89PNG\r\n\x1a\n"
        ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
        ihdr_chunk = b"IHDR" + ihdr
        ihdr_crc = struct.pack(">I", zlib.crc32(ihdr_chunk))
        raw = b""
        for _ in range(h):
            raw += b"\x00" + bytes(color) * w
        idat = zlib.compress(raw)
        idat_chunk = b"IDAT" + idat
        idat_crc = struct.pack(">I", zlib.crc32(idat_chunk))
        iend = b"IEND"
        iend_crc = struct.pack(">I", zlib.crc32(iend))
        return (sig
                + struct.pack(">I", len(ihdr)) + ihdr_chunk + ihdr_crc
                + struct.pack(">I", len(idat)) + idat_chunk + idat_crc
                + struct.pack(">I", 0) + iend + iend_crc)
    for spec in SHOTS:
        spec["path"].parent.mkdir(parents=True, exist_ok=True)
        spec["path"].write_bytes(make_png(720, 360))
PYEOF

# --- 2. Pre-delete any 'Packages' note from prior runs (agent creates fresh) ---
open -a "Notes" 2>/dev/null || true
sleep 3
osascript << 'APPLEOF' 2>/dev/null || true
tell application "Notes"
    try
        set existing to (every note whose name is "Packages")
        repeat with n in existing
            delete n
        end repeat
    end try
end tell
APPLEOF
sleep 1

# --- 3. Record baseline ---
date +%s > /tmp/raycast_screenshot_ocr_aichat_start_ts

echo "Task start ts: $(cat /tmp/raycast_screenshot_ocr_aichat_start_ts)"
echo "=== Setup complete ==="
