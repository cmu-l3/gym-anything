#!/bin/bash
# Setup: raycast_screenshot_ocr_clipboard
#
# Renders 6 real PNG screenshots of warranty pages (real product info,
# real-format warranty codes/serials) to ~/Desktop and ~/Pictures/Screenshots.
# Exactly one contains 'WTY-8X4' + 'REF-9X4Q-22847'. The others are distractors.
# Opens Apple Notes and creates an 'Equipment Inventory' note with 'Serial: '
# ready for the agent to paste into. Sets system clipboard to 'call mom after 6'.

set -euo pipefail
echo "=== Setup: raycast_screenshot_ocr_clipboard ==="

DESKTOP="/Users/lume/Desktop"
PIC_SCREENSHOTS="/Users/lume/Pictures/Screenshots"
mkdir -p "$DESKTOP" "$PIC_SCREENSHOTS"

# --- 1. Ensure Raycast running + dismiss permission dialogs ---
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
                if exists button "Allow" of front window then
                    click button "Allow" of front window
                else if exists button "OK" of front window then
                    click button "OK" of front window
                else if exists button "Don't Allow" of front window then
                    click button "Don't Allow" of front window
                end if
            end tell
        end repeat
    end try
end tell
APPLEOF
    sleep 1
done

# --- 2. Wipe any previous screenshots from prior runs ---
rm -f "$DESKTOP"/screenshot_warranty_*.png 2>/dev/null || true
rm -f "$PIC_SCREENSHOTS"/screenshot_warranty_*.png 2>/dev/null || true

# --- 3. Render 6 warranty screenshots (real product info) via PyObjC ---
python3 << 'PYEOF'
import sys
from pathlib import Path

DESKTOP = Path("/Users/lume/Desktop")
PIC = Path("/Users/lume/Pictures/Screenshots")
PIC.mkdir(parents=True, exist_ok=True)

# Real product warranty content. The TARGET screenshot has the specific
# 'WTY-8X4' code and the serial 'REF-9X4Q-22847'.
SCREENSHOTS = [
    {
        "path": DESKTOP / "screenshot_warranty_lg_fridge.png",
        "title": "LG French-Door Refrigerator — Warranty",
        "lines": [
            "LG Electronics USA — Limited Warranty",
            "Model: LRMVS3006S (French-Door, 30 cu ft)",
            "Warranty Claim: WTY-8X4",
            "Serial: REF-9X4Q-22847",
            "Purchase date: March 4, 2026",
            "Coverage: 1-year parts & labor, 7-year sealed system",
            "Register at lg.com/us/support/register-product",
            "Customer support: 1-800-243-0000",
        ],
    },
    {
        "path": DESKTOP / "screenshot_warranty_lg_washer.png",
        "title": "LG Front-Load Washing Machine — Warranty",
        "lines": [
            "LG Electronics USA — Limited Warranty",
            "Model: WM4000HBA (front-load, 4.5 cu ft)",
            "Warranty Claim: WTY-3K9",
            "Serial: WMC-5512-B82",
            "Purchase date: January 12, 2026",
            "Coverage: 1-year parts & labor, 10-year direct-drive motor",
            "Register at lg.com/us/support/register-product",
            "Customer support: 1-800-243-0000",
        ],
    },
    {
        "path": DESKTOP / "screenshot_warranty_lg_dryer.png",
        "title": "LG Electric Dryer — Warranty",
        "lines": [
            "LG Electronics USA — Limited Warranty",
            "Model: DLEX4000B (electric, 7.4 cu ft)",
            "Warranty Claim: WTY-5J2",
            "Serial: DRY-7741-N09",
            "Purchase date: January 12, 2026",
            "Coverage: 1-year parts & labor, 10-year direct-drive motor",
            "Register at lg.com/us/support/register-product",
            "Customer support: 1-800-243-0000",
        ],
    },
    {
        "path": PIC / "screenshot_warranty_sony_tv.png",
        "title": "Sony BRAVIA XR OLED TV — Warranty",
        "lines": [
            "Sony Electronics Inc. — Limited Warranty",
            "Model: XR-65A95L (65\" 4K OLED, BRAVIA XR)",
            "Warranty Claim: WTY-7P1",
            "Serial: TV-2293-OLED",
            "Purchase date: February 28, 2026",
            "Coverage: 1-year parts & labor",
            "Register at sony.com/electronics/support/product-registration",
            "Customer support: 1-800-222-7669",
        ],
    },
    {
        "path": PIC / "screenshot_warranty_sonos_speakers.png",
        "title": "Sonos Era 300 Speakers — Warranty",
        "lines": [
            "Sonos Inc. — One-Year Limited Warranty",
            "Model: Era 300 (pair)",
            "Warranty Claim: WTY-2F6",
            "Serial: SPK-7711-A2",
            "Purchase date: April 2, 2026",
            "Coverage: 1-year manufacturing defects",
            "Register at sonos.com/register",
            "Customer support: 1-800-680-2345",
        ],
    },
    {
        "path": PIC / "screenshot_warranty_shure_mic.png",
        "title": "Shure SM7B Microphone — Warranty",
        "lines": [
            "Shure Incorporated — Two-Year Limited Warranty",
            "Model: SM7B (dynamic cardioid microphone)",
            "Warranty Claim: WTY-9N3",
            "Serial: MIC-3309-K1",
            "Purchase date: March 22, 2026",
            "Coverage: 2-year manufacturer warranty",
            "Register at shure.com/en-US/support/product-registration",
            "Customer support: 1-847-600-2000",
        ],
    },
]

try:
    from AppKit import (NSImage, NSColor, NSFont, NSBitmapImageRep,
                        NSPNGFileType, NSRectFill)
    from AppKit import NSAttributedString, NSMakeRect, NSMakeSize
    for spec in SCREENSHOTS:
        W, H = 720, 360
        img = NSImage.alloc().initWithSize_(NSMakeSize(W, H))
        img.lockFocus()
        # White background
        NSColor.whiteColor().setFill()
        NSRectFill(NSMakeRect(0, 0, W, H))
        # Title bar (light gray)
        NSColor.colorWithCalibratedRed_green_blue_alpha_(0.92, 0.92, 0.94, 1.0).setFill()
        NSRectFill(NSMakeRect(0, H - 40, W, 40))
        # Title text
        title_font = NSFont.boldSystemFontOfSize_(15)
        title_attrs = {"NSFont": title_font, "NSColor": NSColor.blackColor()}
        nsa_title = NSAttributedString.alloc().initWithString_attributes_(spec["title"], title_attrs)
        nsa_title.drawInRect_(NSMakeRect(16, H - 32, W - 32, 26))
        # Body text
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
    print(f"PyObjC render failed: {exc}", file=sys.stderr)
    # Fallback: write tiny placeholder PNGs so verification structure works
    import struct, zlib
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
    for spec in SCREENSHOTS:
        spec["path"].parent.mkdir(parents=True, exist_ok=True)
        spec["path"].write_bytes(make_png(720, 360))
PYEOF

# --- 4. Open Apple Notes and create the 'Equipment Inventory' note ---
open -a "Notes" 2>/dev/null || true
sleep 3
# Dismiss Notes welcome / iCloud account dialogs
for _i in $(seq 1 4); do
    osascript << 'APPLEOF' 2>/dev/null || true
tell application "System Events"
    try
        repeat with proc in (every application process whose frontmost is true)
            tell proc
                if exists button "Not Now" of front window then
                    click button "Not Now" of front window
                else if exists button "Continue" of front window then
                    click button "Continue" of front window
                end if
            end tell
        end repeat
    end try
end tell
APPLEOF
    sleep 1
done

osascript << 'APPLEOF' 2>/dev/null || true
tell application "Notes"
    activate
    -- Delete any existing 'Equipment Inventory' notes
    try
        set existing to (every note whose name is "Equipment Inventory")
        repeat with n in existing
            delete n
        end repeat
    end try
    -- Create the note with 'Serial: ' ready for paste
    make new note with properties {name:"Equipment Inventory", body:"Equipment Inventory<br><br>Product: LG French-door refrigerator<br>Serial: "}
end tell
APPLEOF
sleep 2

# --- 5. Set system clipboard to 'call mom after 6' (the value to preserve) ---
printf '%s' "call mom after 6" | pbcopy

# --- 6. Record baseline ---
date +%s > /tmp/raycast_screenshot_ocr_clipboard_start_ts

echo "Initial clipboard: $(pbpaste)"
echo "Task start ts:     $(cat /tmp/raycast_screenshot_ocr_clipboard_start_ts)"
echo "=== Setup complete ==="
