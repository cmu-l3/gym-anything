#!/bin/bash
# Setup: raycast_clipboard_formats_destructive
#
# Builds a messy real-world clipboard state:
#   - creates real receipt.pdf + warranty.png in ~/Desktop/Materials/
#   - creates empty ~/Desktop/Household Inbox
#   - opens a Mail draft titled "May 2026 newsletter — staff update"
#   - seeds Raycast Clipboard History via 9 successive system-pasteboard writes
#     (Raycast watches the pasteboard so each becomes a separate entry):
#       1. RICH-TEXT May newsletter signature (HTML + plain on the same paste)
#       2. PLAIN-TEXT version of the same signature
#       3. Grouped file-copy (receipt.pdf + warranty.png)
#       4. Color value "#3498DB"
#       5. Bank OTP "123456"
#       6. "buy groceries"
#       7. "team meeting at 3pm"
#       8. "remember umbrella"
#       9. "call mom after 6"   <- final active clipboard
#
# No entries are pre-pinned; the agent must pin "call mom after 6" before
# destructive deletion to preserve it.

set -euo pipefail
echo "=== Setup: raycast_clipboard_formats_destructive ==="

DESKTOP="/Users/lume/Desktop"
MATERIALS="$DESKTOP/Materials"
INBOX="$DESKTOP/Household Inbox"

# --- 1. Ensure Raycast running + dismiss permission dialogs ---
if ! pgrep -x "Raycast" > /dev/null 2>&1; then
    open -a "Raycast" 2>/dev/null || true
    for i in $(seq 1 15); do
        if pgrep -x "Raycast" > /dev/null 2>&1; then break; fi
        sleep 2
    done
fi
sleep 3

for _i in $(seq 1 6); do
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

# --- 2. Create ~/Desktop/Materials with REAL receipt.pdf + warranty.png ---
mkdir -p "$MATERIALS" "$INBOX"
# Wipe any stale Inbox contents (agent's grouped paste must produce these files fresh)
rm -f "$INBOX"/*.pdf "$INBOX"/*.png 2>/dev/null || true
rm -f "$MATERIALS/receipt.pdf" "$MATERIALS/warranty.png" 2>/dev/null || true

# receipt.pdf — real receipt text rendered via cupsfilter into a real PDF
cat > /tmp/_receipt_src.txt << 'EOF'
Amazon.com Order Summary
Order #112-9876543-1234567
Placed: April 18, 2026
Ship to: Lume Household, 1742 NW Glisan St, Portland OR 97209
---------------------------------------------------
Items:
  1 x Apple AirPods Pro (USB-C, 2nd Gen)        $249.00
  1 x Anker 622 Magnetic Battery (MagGo)         $39.99
  1 x USB-C to Lightning cable, 2 m              $14.99
Subtotal:                                       $303.98
Shipping & handling:                              $0.00
Tax (Multnomah Co.):                              $0.00
Total:                                          $303.98
---------------------------------------------------
Paid with: Visa ending in 4242
Returns accepted until May 18, 2026.
EOF
cupsfilter -e /tmp/_receipt_src.txt > "$MATERIALS/receipt.pdf" 2>/dev/null || true

# warranty.png — real product warranty text rendered into a PNG via textutil/sips
# Use a small AppleScript-rendered text-to-image fallback (Quartz via Python).
python3 << 'PYEOF'
import subprocess, sys
from pathlib import Path
out = Path("/Users/lume/Desktop/Materials/warranty.png")
text = (
    "AppleCare+ Limited Warranty Coverage\n"
    "Product: Apple AirPods Pro (2nd Gen)\n"
    "Serial: WTY-MX4Q-7821-PRO\n"
    "Purchase date: April 18, 2026\n"
    "Coverage period: 2 years from purchase\n"
    "Covers: defects, battery service, accidental damage (2 incidents)\n"
    "Support: 1-800-275-2273 (1-800-MY-APPLE)\n"
    "Reference apple.com/support/products/airpods for claim filing.\n"
)
# Render text -> PNG via Cocoa (PyObjC, bundled with macOS Python).
try:
    from AppKit import (NSImage, NSColor, NSFont, NSDictionary, NSString,
                        NSAttributedString, NSBitmapImageRep, NSPNGFileType,
                        NSGraphicsContext, NSMakeRect, NSMakeSize)
    from Foundation import NSAttributedString as NSAttr
    size = (560, 240)
    img = NSImage.alloc().initWithSize_(NSMakeSize(*size))
    img.lockFocus()
    NSColor.whiteColor().setFill()
    from AppKit import NSRectFill
    NSRectFill(NSMakeRect(0, 0, *size))
    font = NSFont.fontWithName_size_("Menlo", 12) or NSFont.systemFontOfSize_(12)
    attrs = {"NSFont": font, "NSColor": NSColor.blackColor()}
    nsa = NSAttr.alloc().initWithString_attributes_(text, attrs)
    nsa.drawInRect_(NSMakeRect(16, 8, size[0]-32, size[1]-16))
    rep = NSBitmapImageRep.alloc().initWithFocusedViewRect_(NSMakeRect(0, 0, *size))
    img.unlockFocus()
    png = rep.representationUsingType_properties_(NSPNGFileType, None)
    png.writeToFile_atomically_(str(out), True)
    print(f"WROTE {out}")
except Exception as exc:
    # Fallback: write a tiny valid PNG via Python's stdlib (struct) so the file
    # at least exists at the right path.
    print(f"PyObjC render failed: {exc}; writing placeholder PNG", file=sys.stderr)
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
    out.write_bytes(make_png(560, 240))
PYEOF

ls -la "$MATERIALS/" || true

# --- 3. Open Mail and create the May 2026 newsletter draft ---
open -a "Mail" 2>/dev/null || true
sleep 3
# Dismiss any Mail welcome dialogs
for _i in $(seq 1 4); do
    osascript << 'APPLEOF' 2>/dev/null || true
tell application "System Events"
    try
        if exists button "Not Now" of front window of (first process whose frontmost is true) then
            click button "Not Now" of front window of (first process whose frontmost is true)
        end if
    end try
end tell
APPLEOF
    sleep 1
done
osascript << 'APPLEOF' 2>/dev/null || true
tell application "Mail"
    activate
    make new outgoing message with properties {subject:"May 2026 newsletter — staff update", visible:true, content:"Hi team,

Sharing the May 2026 newsletter draft below for review.

[newsletter body — see attached PDF]

Best,
"}
end tell
APPLEOF
sleep 2

# --- 4. Seed Raycast Clipboard History via 9 successive pasteboard writes ---
# Brief sleeps between each so Raycast's pasteboard watcher captures each one
# as a separate history entry.

# Helper: copy plain text
copy_plain() {
    printf '%s' "$1" | pbcopy
    sleep 1.2
}

# Entry 1: RICH-TEXT signature (HTML + plain on the same pasteboard write)
python3 << 'PYEOF'
from AppKit import NSPasteboard
pb = NSPasteboard.generalPasteboard()
pb.clearContents()
html = ("<html><body style=\"font-family: Helvetica, sans-serif;\">"
        "<p>Best,<br>"
        "<b>Margaret Lin</b><br>"
        "Newsletter Coordinator<br>"
        "<span style=\"color: #666\">Westside Community Center</span></p>"
        "</body></html>")
plain = "Best,\nMargaret Lin\nNewsletter Coordinator\nWestside Community Center"
pb.setString_forType_(html, "public.html")
pb.setString_forType_(plain, "public.utf8-plain-text")
print("seeded rich-text signature")
PYEOF
sleep 1.5

# Entry 2: PLAIN-TEXT version of the same signature
copy_plain "Best,
Margaret Lin
Newsletter Coordinator
Westside Community Center"

# Entry 3: Grouped file copy (receipt.pdf + warranty.png)
osascript << APPLEOF 2>/dev/null || true
set f1 to POSIX file "$MATERIALS/receipt.pdf"
set f2 to POSIX file "$MATERIALS/warranty.png"
set the clipboard to {f1, f2}
APPLEOF
sleep 1.5

# Entry 4: color value
copy_plain "#3498DB"

# Entry 5: bank OTP
copy_plain "123456"

# Entry 6: normal text
copy_plain "buy groceries"

# Entry 7: normal text
copy_plain "team meeting at 3pm"

# Entry 8: normal text
copy_plain "remember umbrella"

# Entry 9: final active clipboard
copy_plain "call mom after 6"

# --- 5. Record baseline ---
date +%s > /tmp/raycast_clipboard_formats_destructive_start_ts

echo "Task start ts: $(cat /tmp/raycast_clipboard_formats_destructive_start_ts)"
echo "Materials:     $(ls -la "$MATERIALS")"
echo "Final clipboard: $(pbpaste)"
echo "=== Setup complete ==="
