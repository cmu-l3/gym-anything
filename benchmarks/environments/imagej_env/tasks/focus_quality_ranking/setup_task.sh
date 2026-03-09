#!/bin/bash
set -e
echo "=== Setting up Focus Quality Assessment task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
sleep 1

# Clean previous results
rm -rf /home/ga/ImageJ_Data/results/*
rm -rf /home/ga/ImageJ_Data/focus_assessment
mkdir -p /home/ga/ImageJ_Data/results
mkdir -p /home/ga/ImageJ_Data/focus_assessment
chown -R ga:ga /home/ga/ImageJ_Data

# Find BBBC005 images
BBBC_DIR=""
for candidate in \
    "/opt/imagej_samples/BBBC005" \
    "/opt/imagej_samples/BBBC005/BBBC005_v1_images" \
    "/home/ga/ImageJ_Data/raw/BBBC005" \
    "/home/ga/ImageJ_Data/raw/BBBC005/BBBC005_v1_images"; do
    if [ -d "$candidate" ]; then
        # Check if it contains TIF files (directly or in subdirectories)
        TIF_COUNT=$(find "$candidate" -maxdepth 2 -name "*.TIF" -o -name "*.tif" 2>/dev/null | wc -l)
        if [ "$TIF_COUNT" -gt 0 ]; then
            BBBC_DIR="$candidate"
            echo "Found BBBC005 images at: $BBBC_DIR ($TIF_COUNT TIF files)"
            break
        fi
    fi
done

USE_FALLBACK=false

if [ -n "$BBBC_DIR" ]; then
    echo "Selecting images across blur levels..."
    # BBBC005 naming: SIMCEPImages_AXX_CYY_FZ_sNN_wW.TIF
    # w1 = DAPI channel (nuclei), s01-s05 = blur levels (1=sharp, 5=blur)
    
    SELECTED=0
    # Select specific images spanning blur levels to ensure StdDev ranking works
    # We select w1 (nuclei) images
    
    # Try to find images for each blur level
    for blur in 01 02 03 04 05; do
        # Find up to 2 images for this blur level
        FOUND_FILES=$(find "$BBBC_DIR" -maxdepth 2 \( -name "*_s${blur}_w1.TIF" -o -name "*_s${blur}_w1.tif" \) 2>/dev/null | sort | head -2)
        
        for f in $FOUND_FILES; do
            if [ $SELECTED -lt 8 ]; then
                # Extract cell count info from filename for variety if possible
                BASENAME=$(basename "$f")
                
                # Create simplified name preserving blur level for the task
                # e.g., focus_s01_C3.tif
                CELL_ID=$(echo "$BASENAME" | grep -oP 'C\d+' | head -1)
                [ -z "$CELL_ID" ] && CELL_ID="img${SELECTED}"
                
                NEWNAME="focus_s${blur}_${CELL_ID}.tif"
                cp "$f" "/home/ga/ImageJ_Data/focus_assessment/$NEWNAME"
                echo "  Copied: $BASENAME -> $NEWNAME"
                SELECTED=$((SELECTED + 1))
            fi
        done
    done

    # Fill up to 8 images if needed
    if [ $SELECTED -lt 8 ]; then
        echo "Adding extra images to reach count of 8..."
        EXTRA_FILES=$(find "$BBBC_DIR" -maxdepth 2 \( -name "*_w1.TIF" -o -name "*_w1.tif" \) 2>/dev/null | sort | head -20)
        for f in $EXTRA_FILES; do
            if [ $SELECTED -ge 8 ]; then break; fi
            BASENAME=$(basename "$f")
            # Avoid overwriting
            if [ ! -f "/home/ga/ImageJ_Data/focus_assessment/$BASENAME" ]; then
                cp "$f" "/home/ga/ImageJ_Data/focus_assessment/extra_$BASENAME"
                SELECTED=$((SELECTED + 1))
            fi
        done
    fi

    if [ $SELECTED -lt 4 ]; then
        echo "Warning: Not enough BBBC005 images found. Using fallback."
        USE_FALLBACK=true
    else
        echo "Successfully prepared $SELECTED images."
    fi
else
    echo "BBBC005 not found. Using fallback."
    USE_FALLBACK=true
fi

# Fallback generation if real data missing
if [ "$USE_FALLBACK" = true ]; then
    echo "Generating fallback focus test images using Fiji..."
    
    # Create a macro that generates blurred versions of Blobs sample
    cat > /tmp/generate_focus_images.ijm << 'MACROEOF'
run("Blobs (25K)");
original = getTitle();
sigmas = newArray(0, 1, 2, 4, 6, 8, 12, 20);
names = newArray("focus_s01_sharp.tif", "focus_s01_slight.tif", "focus_s02_mild.tif",
                 "focus_s03_moderate.tif", "focus_s03_medium.tif", "focus_s04_strong.tif",
                 "focus_s04_heavy.tif", "focus_s05_severe.tif");
outputDir = "/home/ga/ImageJ_Data/focus_assessment/";
for (i = 0; i < sigmas.length; i++) {
    selectWindow(original);
    run("Duplicate...", "title=temp");
    if (sigmas[i] > 0) {
        run("Gaussian Blur...", "sigma=" + sigmas[i]);
    }
    saveAs("Tiff", outputDir + names[i]);
    close();
}
selectWindow(original);
close();
MACROEOF

    # Kill any running Fiji first
    pkill -f "fiji\|Fiji\|ImageJ" 2>/dev/null || true
    sleep 2
    
    # Launch Fiji headless-ish to run macro
    FIJI_PATH=$(find_fiji_executable 2>/dev/null || echo "/usr/local/bin/fiji")
    "$FIJI_PATH" -macro /tmp/generate_focus_images.ijm > /dev/null 2>&1 &
    MACRO_PID=$!
    
    # Wait for images
    for i in {1..60}; do
        FILE_COUNT=$(ls /home/ga/ImageJ_Data/focus_assessment/*.tif 2>/dev/null | wc -l)
        if [ "$FILE_COUNT" -ge 8 ]; then
            echo "Fallback images generated."
            break
        fi
        sleep 2
    done
    kill $MACRO_PID 2>/dev/null || true
    pkill -f "fiji\|Fiji\|ImageJ" 2>/dev/null || true
fi

# Save list of input images for verification
ls -1 /home/ga/ImageJ_Data/focus_assessment/*.tif 2>/dev/null | xargs -I{} basename {} > /tmp/focus_image_list.txt
chown -R ga:ga /home/ga/ImageJ_Data

# Launch Fiji for the agent
echo "Launching Fiji..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Check for Fiji executable
FIJI_PATH=$(find_fiji_executable 2>/dev/null || echo "fiji")
if [ -z "$FIJI_PATH" ]; then FIJI_PATH="fiji"; fi

su - ga -c "DISPLAY=:1 $FIJI_PATH &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|Fiji"; then
        echo "Fiji window detected"
        break
    fi
    sleep 1
done

# Focus window
DISPLAY=:1 wmctrl -a "ImageJ" 2>/dev/null || DISPLAY=:1 wmctrl -a "Fiji" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="