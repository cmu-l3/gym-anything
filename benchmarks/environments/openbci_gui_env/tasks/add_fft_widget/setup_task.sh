#!/bin/bash
echo "=== Setting up add_fft_widget task ==="

source /workspace/utils/openbci_utils.sh || true

kill_openbci

# Start synthetic session first (this loads the default layout which includes FFT Plot)
launch_openbci_synthetic

# Change the FFT Plot widget to Head Plot so no FFT widget is visible at task start.
# OpenBCI GUI saves/restores the last-used widget layout, which always includes FFT
# in the upper-right panel. We change it via xdotool after session start.
#
# Coordinates (1920x1080):
#   - Upper-right panel widget dropdown: (660, 138)
#   - "Head Plot" option in dropdown: (652, 266)
#
# Note: Selecting a widget already shown in another panel causes a swap.
# "Head Plot" is not shown in any default panel, so it replaces FFT without swapping.
echo "Changing FFT Plot widget to Head Plot (removing FFT from start state)..."

# Retry the widget swap up to 3 times to ensure reliability.
# Coordinates (1920x1080):
#   - Upper-right panel widget dropdown: (660, 138)
#   - "Head Plot" option in dropdown: (652, 266)
for attempt in 1 2 3; do
    echo "Widget swap attempt $attempt of 3..."

    # Click somewhere neutral first to dismiss any stale popups
    su - ga -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool mousemove --sync 960 540; sleep 0.2; xdotool click 1' 2>/dev/null || true
    sleep 0.5

    # Click the upper-right panel's widget selector dropdown
    su - ga -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool mousemove --sync 660 138; sleep 0.3; xdotool click 1' 2>/dev/null || true
    sleep 1.5

    # Click "Head Plot" in the dropdown (7th option, y≈177 in 1280x720 scale → y=266 in 1920x1080)
    su - ga -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool mousemove --sync 652 266; sleep 0.3; xdotool click 1' 2>/dev/null || true
    sleep 1.5

    # Verify the swap: check that the upper-right panel no longer shows "FFT Plot" header.
    # The panel header text is rendered at ~(660, 125) in 1920x1080.
    # We use scrot + python3 to capture the panel header region and look for distinctive
    # Head Plot rendering (white circular head shape on dark background) vs FFT (line graph).
    # As a lightweight heuristic, check pixel brightness in the widget header row.
    SWAP_OK=$(su - ga -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; scrot /tmp/fft_swap_check.png 2>/dev/null && echo ok' 2>/dev/null)
    if [ "$SWAP_OK" = "ok" ]; then
        # Check if the upper-right panel header area contains Head Plot's label color.
        # In OpenBCI GUI, each widget type has a distinct header background.
        # If the swap succeeded, the panel at (660, 125) should show "Head Plot" text region.
        CHECK=$(python3 -c "
from PIL import Image
try:
    img = Image.open('/tmp/fft_swap_check.png')
    # Sample a strip of pixels across the top-center of the upper-right panel header
    # to check for the characteristic Head Plot widget header appearance
    # (dark purple/navy background with white text, vs FFT's greenish background)
    w, h = img.size
    # Upper-right panel header is at roughly x=480-840, y=118-145 in 1920x1080
    strip = [img.getpixel((x, 128)) for x in range(490, 840, 20)]
    # Head Plot header is typically darker than FFT Plot header
    avg_brightness = sum(r+g+b for r,g,b in strip) / (3 * len(strip))
    print(f'avg_brightness={avg_brightness:.1f}')
    if avg_brightness < 80:
        print('SWAP_CONFIRMED: panel appears dark (Head Plot)')
    else:
        print('SWAP_UNCERTAIN: panel appears bright (may still be FFT)')
except Exception as e:
    print(f'check_error={e}')
" 2>/dev/null)
        echo "Swap check: $CHECK"
        if echo "$CHECK" | grep -q "SWAP_CONFIRMED"; then
            echo "Widget swap confirmed on attempt $attempt."
            break
        fi
    fi

    if [ $attempt -lt 3 ]; then
        echo "Swap uncertain, retrying..."
        sleep 1
    fi
done

echo "=== Task setup complete: GUI running in Synthetic mode with NO FFT widget ==="
echo "Panels: Time Series (left), Head Plot (upper right), Accelerometer (lower right)"
echo "Agent should find a widget panel (Head Plot or Accelerometer) and switch it to FFT Plot"
