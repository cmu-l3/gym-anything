#!/bin/bash
echo "=== Installing Autopsy Digital Forensics Platform ==="

export DEBIAN_FRONTEND=noninteractive

# Disable needrestart to prevent SSH restarts during package installation
mkdir -p /etc/needrestart 2>/dev/null
echo '$nrconf{restart} = "a";' > /etc/needrestart/needrestart.conf 2>/dev/null || true
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
systemctl stop unattended-upgrades 2>/dev/null || true
systemctl disable unattended-upgrades 2>/dev/null || true

apt-get update -q

# ============================================================
# Step 1: Install Java 17
# ============================================================
echo "=== Installing OpenJDK 17 ==="
apt-get install -y -q openjdk-17-jdk 2>&1

JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
[ ! -d "$JAVA_HOME" ] && JAVA_HOME=$(find /usr/lib/jvm -maxdepth 1 -type d -name 'java-17*' 2>/dev/null | head -1)
export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"
echo "JAVA_HOME=$JAVA_HOME"
java -version 2>&1 || true

# ============================================================
# Step 2: Install system dependencies
# ============================================================
echo "=== Installing system dependencies ==="
apt-get install -y -q \
    wget curl unzip \
    xdotool wmctrl scrot x11-utils \
    python3-pip python3-pil testdisk \
    dosfstools ntfs-3g mtools 2>&1

apt-get clean 2>/dev/null || true
echo "Disk: $(df -h / 2>/dev/null | tail -1)"

# ============================================================
# Step 3: Download and install Autopsy
# ============================================================
echo "=== Downloading Autopsy ==="
AUTOPSY_VERSION="4.21.0"

# Download with retries
for attempt in 1 2 3; do
    echo "Download attempt $attempt..."
    wget --timeout=300 -O /tmp/autopsy.zip \
        "https://github.com/sleuthkit/autopsy/releases/download/autopsy-${AUTOPSY_VERSION}/autopsy-${AUTOPSY_VERSION}.zip" 2>&1
    if [ -s /tmp/autopsy.zip ]; then
        echo "Autopsy ZIP downloaded: $(stat -c%s /tmp/autopsy.zip) bytes"
        break
    fi
    echo "Download failed, retrying in 5s..."
    sleep 5
done

if [ ! -s /tmp/autopsy.zip ]; then
    echo "FATAL: Could not download Autopsy after 3 attempts"
    exit 1
fi

echo "Extracting Autopsy..."
unzip -q /tmp/autopsy.zip -d /opt/ 2>&1
rm -f /tmp/autopsy.zip

AUTOPSY_DIR="/opt/autopsy-${AUTOPSY_VERSION}"
[ ! -d "$AUTOPSY_DIR" ] && AUTOPSY_DIR=$(find /opt -maxdepth 1 -type d -name 'autopsy*' 2>/dev/null | head -1)

if [ -z "$AUTOPSY_DIR" ] || [ ! -d "$AUTOPSY_DIR" ]; then
    echo "FATAL: Autopsy directory not found"
    exit 1
fi

echo "Autopsy directory: $AUTOPSY_DIR"

# ============================================================
# Step 4: Install The Sleuth Kit Java bindings (CRITICAL)
# Must happen BEFORE unix_setup.sh so it passes the check
# ============================================================
echo "=== Installing TSK Java bindings ==="

TSK_VERSION="4.12.1"
TSK_DEB="/tmp/sleuthkit-java.deb"

# Download with retries - this is critical for Autopsy to work
for attempt in 1 2 3; do
    echo "TSK download attempt $attempt..."
    wget --timeout=120 -O "$TSK_DEB" \
        "https://github.com/sleuthkit/sleuthkit/releases/download/sleuthkit-${TSK_VERSION}/sleuthkit-java_${TSK_VERSION}-1_amd64.deb" 2>&1
    if [ -s "$TSK_DEB" ]; then
        echo "TSK .deb downloaded: $(stat -c%s "$TSK_DEB") bytes"
        break
    fi
    echo "TSK download failed, retrying in 5s..."
    rm -f "$TSK_DEB"
    sleep 5
done

if [ -s "$TSK_DEB" ]; then
    echo "Installing TSK Java .deb (provides JNI + JAR)..."
    dpkg -i "$TSK_DEB" 2>&1 || true
    apt-get install -f -y -q 2>&1 || true
    rm -f "$TSK_DEB"

    # Now install sleuthkit from apt for CLI tools (fls, icat, mmls, img_stat)
    # Use --force-overwrite to handle libtsk.so.19 conflict with sleuthkit-java deb
    echo "Installing sleuthkit CLI tools from apt..."
    apt-get install -y -q -o Dpkg::Options::='--force-overwrite' sleuthkit 2>&1 || true

    # CRITICAL: Create JNI symlinks in Java's default library path
    # OpenJDK 17 on Ubuntu only searches /usr/java/packages/lib by default
    mkdir -p /usr/java/packages/lib
    for f in /usr/lib/x86_64-linux-gnu/libtsk_jni*; do
        [ -f "$f" ] && ln -sf "$f" /usr/java/packages/lib/$(basename "$f")
    done
    echo "JNI symlinks created in /usr/java/packages/lib/"
    ls -la /usr/java/packages/lib/libtsk_jni* 2>/dev/null || true

    # Verify JNI library installed
    if find /usr/lib -name "libtsk_jni.so" 2>/dev/null | grep -q .; then
        echo "TSK JNI library: INSTALLED"
    else
        echo "WARNING: TSK JNI library not found after install"
    fi

    # Verify JAR
    if ls /usr/share/java/sleuthkit-*.jar 2>/dev/null | grep -q .; then
        echo "TSK JAR: INSTALLED"
    else
        echo "WARNING: TSK JAR not found"
    fi

    # Verify CLI tools
    for tool in fls icat mmls img_stat; do
        command -v "$tool" >/dev/null 2>&1 && echo "TSK $tool: OK" || echo "TSK $tool: NOT FOUND"
    done
else
    echo "WARNING: Could not download TSK .deb"
    echo "Installing sleuthkit from apt (CLI tools only, no Java bindings)..."
    apt-get install -y -q sleuthkit 2>&1 || true
fi

# ============================================================
# Step 5: Configure Autopsy
# ============================================================
echo "=== Configuring Autopsy ==="
cd "$AUTOPSY_DIR"

# Run unix_setup.sh (should pass now that TSK is installed)
if [ -f "unix_setup.sh" ]; then
    chmod +x unix_setup.sh
    bash unix_setup.sh 2>&1 || echo "unix_setup.sh returned non-zero"
fi

# Set JDK path in autopsy.conf
AUTOPSY_CONF="$AUTOPSY_DIR/etc/autopsy.conf"
if [ -f "$AUTOPSY_CONF" ]; then
    sed -i "s|^#*jdkhome=.*|jdkhome=\"$JAVA_HOME\"|" "$AUTOPSY_CONF" 2>/dev/null || true
    grep -q "^jdkhome=" "$AUTOPSY_CONF" 2>/dev/null || echo "jdkhome=\"$JAVA_HOME\"" >> "$AUTOPSY_CONF"

    # CRITICAL: Limit JVM heap to 2g to prevent OOM on the VM
    sed -i 's/-J-Xmx[0-9]*[gGmM]/-J-Xmx2g/g' "$AUTOPSY_CONF" 2>/dev/null || true
    echo "JVM memory limited to 2g in autopsy.conf"
fi

chmod +x "$AUTOPSY_DIR/bin/autopsy" 2>/dev/null || true
ln -sf "$AUTOPSY_DIR/bin/autopsy" /usr/local/bin/autopsy

# ============================================================
# Step 6: Download real forensic test disk images
# Primary source: DFTT (Digital Forensic Tool Testing) project
# These are standard forensic test images used by the community.
# Tasks expect: ntfs_undel.dd, jpeg_search.dd
# ============================================================
echo "=== Downloading forensic disk images ==="
mkdir -p /home/ga/evidence

# --- Helper: validate a downloaded file is a real disk image, not HTML error ---
validate_download() {
    local file="$1"
    if [ ! -s "$file" ]; then return 1; fi
    # Check if it's an HTML error page
    if head -c 100 "$file" 2>/dev/null | grep -qi "html\|<!DOCTYPE\|404\|error"; then
        echo "  Invalid download (HTML): $file"
        rm -f "$file"
        return 1
    fi
    return 0
}

# ============================================================
# Download DFTT #7: NTFS Undelete test image (6MB, real forensic test data)
# Source: https://dftt.sourceforge.net/test7/index.html
# Contains: NTFS filesystem with deleted files for recovery testing
# ============================================================
echo "Downloading DFTT #7 NTFS Undelete test image..."
NTFS_OK=false
for attempt in 1 2 3; do
    echo "  Attempt $attempt..."
    wget --timeout=60 --tries=1 -q -O /tmp/7-undel-ntfs.zip \
        "https://prdownloads.sourceforge.net/dftt/7-undel-ntfs.zip?download" 2>&1 || true
    if [ -s /tmp/7-undel-ntfs.zip ]; then
        # Verify it's a real ZIP
        if file /tmp/7-undel-ntfs.zip 2>/dev/null | grep -qi "zip"; then
            echo "  ZIP downloaded ($(stat -c%s /tmp/7-undel-ntfs.zip) bytes)"
            cd /tmp && unzip -o -q 7-undel-ntfs.zip 2>&1 || true
            # ZIP extracts to subdirectory: 7-undel-ntfs/7-ntfs-undel.dd
            EXTRACTED=$(find /tmp -maxdepth 2 -name "7-ntfs-undel.dd" -type f 2>/dev/null | head -1)
            if [ -s "$EXTRACTED" ]; then
                mv "$EXTRACTED" /home/ga/evidence/ntfs_undel.dd
                echo "  DFTT ntfs_undel.dd: $(stat -c%s /home/ga/evidence/ntfs_undel.dd) bytes"
                NTFS_OK=true
            else
                echo "  ZIP extracted but dd file not found"
            fi
            rm -rf /tmp/7-undel-ntfs.zip /tmp/7-undel-ntfs 2>/dev/null || true
            break
        fi
    fi
    rm -f /tmp/7-undel-ntfs.zip
    sleep 3
done

# Fallback: try NIST CFReDS deleted file recovery image
if [ "$NTFS_OK" = false ]; then
    echo "  DFTT download failed, trying NIST CFReDS..."
    wget --timeout=60 --tries=2 -q -O /tmp/dfr-01-ntfs.dd.bz2 \
        "https://cfreds-archive.nist.gov/dfr-images/dfr-01-ntfs.dd.bz2" 2>&1 || true
    if [ -s /tmp/dfr-01-ntfs.dd.bz2 ]; then
        bunzip2 /tmp/dfr-01-ntfs.dd.bz2 2>/dev/null || true
        if [ -s /tmp/dfr-01-ntfs.dd ]; then
            mv /tmp/dfr-01-ntfs.dd /home/ga/evidence/ntfs_undel.dd
            echo "  CFReDS ntfs_undel.dd: $(stat -c%s /home/ga/evidence/ntfs_undel.dd) bytes"
            NTFS_OK=true
        fi
    fi
    rm -f /tmp/dfr-01-ntfs.dd.bz2
fi

# Last resort: create NTFS image with realistic forensic content
if [ "$NTFS_OK" = false ]; then
    echo "  All downloads failed. Creating local NTFS image with forensic content..."
    dd if=/dev/zero of=/home/ga/evidence/ntfs_undel.dd bs=1M count=20 2>/dev/null
    if command -v mkntfs >/dev/null 2>&1; then
        mkntfs -F -L "USB_EVIDENCE" /home/ga/evidence/ntfs_undel.dd 2>/dev/null || \
        mkfs.vfat -F 32 -n "USBEVIDENCE" /home/ga/evidence/ntfs_undel.dd 2>/dev/null || true
    else
        mkfs.vfat -F 32 -n "USBEVIDENCE" /home/ga/evidence/ntfs_undel.dd 2>/dev/null || true
    fi
    mkdir -p /tmp/ev_ntfs
    if mount -o loop /home/ga/evidence/ntfs_undel.dd /tmp/ev_ntfs 2>/dev/null; then
        mkdir -p /tmp/ev_ntfs/{Documents,Logs,Config}
        # Download real text content from public domain sources for realism
        wget --timeout=15 -q -O /tmp/ev_ntfs/Documents/readme.txt \
            "https://www.gutenberg.org/files/11/11-0.txt" 2>/dev/null || \
            echo "Project Gutenberg - Alice in Wonderland excerpt" > /tmp/ev_ntfs/Documents/readme.txt
        # Truncate to reasonable size for forensic scenario
        head -200 /tmp/ev_ntfs/Documents/readme.txt > /tmp/ev_ntfs/Documents/recovered_doc.txt 2>/dev/null
        rm -f /tmp/ev_ntfs/Documents/readme.txt 2>/dev/null || true
        cp /etc/hostname /tmp/ev_ntfs/Config/ 2>/dev/null || true
        cp /etc/os-release /tmp/ev_ntfs/Config/ 2>/dev/null || true
        date -u '+%Y-%m-%dT%H:%M:%SZ' > /tmp/ev_ntfs/Config/imaging_timestamp.txt
        # Create then delete a file (forensic artifact for undelete testing)
        echo "SENSITIVE: internal-access-key-2024-abc123" > /tmp/ev_ntfs/Documents/credentials.txt
        sync
        rm -f /tmp/ev_ntfs/Documents/credentials.txt 2>/dev/null || true
        sync
        umount /tmp/ev_ntfs 2>/dev/null || true
    fi
    rmdir /tmp/ev_ntfs 2>/dev/null || true
    echo "  Local ntfs_undel.dd: $(stat -c%s /home/ga/evidence/ntfs_undel.dd 2>/dev/null) bytes"
fi

# ============================================================
# Download DFTT #8: JPEG Search test image (10MB, real forensic test data)
# Source: https://dftt.sourceforge.net/test8/index.html
# Contains: NTFS filesystem with embedded JPEG files for search testing
# ============================================================
echo "Downloading DFTT #8 JPEG Search test image..."
JPEG_OK=false
for attempt in 1 2 3; do
    echo "  Attempt $attempt..."
    wget --timeout=60 --tries=1 -q -O /tmp/8-jpeg-search.zip \
        "https://prdownloads.sourceforge.net/dftt/8-jpeg-search.zip?download" 2>&1 || true
    if [ -s /tmp/8-jpeg-search.zip ]; then
        if file /tmp/8-jpeg-search.zip 2>/dev/null | grep -qi "zip"; then
            echo "  ZIP downloaded ($(stat -c%s /tmp/8-jpeg-search.zip) bytes)"
            cd /tmp && unzip -o -q 8-jpeg-search.zip 2>&1 || true
            # ZIP extracts to subdirectory: 8-jpeg-search/8-jpeg-search.dd
            EXTRACTED=$(find /tmp -maxdepth 2 -name "8-jpeg-search.dd" -type f 2>/dev/null | head -1)
            if [ -s "$EXTRACTED" ]; then
                mv "$EXTRACTED" /home/ga/evidence/jpeg_search.dd
                echo "  DFTT jpeg_search.dd: $(stat -c%s /home/ga/evidence/jpeg_search.dd) bytes"
                JPEG_OK=true
            else
                echo "  ZIP extracted but dd file not found"
            fi
            rm -rf /tmp/8-jpeg-search.zip /tmp/8-jpeg-search 2>/dev/null || true
            break
        fi
    fi
    rm -f /tmp/8-jpeg-search.zip
    sleep 3
done

# Fallback: create FAT image with real photographs downloaded from the web
if [ "$JPEG_OK" = false ]; then
    echo "  DFTT download failed. Creating FAT image with real photographs..."
    dd if=/dev/zero of=/home/ga/evidence/jpeg_search.dd bs=1M count=10 2>/dev/null
    mkfs.vfat -F 16 -n "JPGSEARCH" /home/ga/evidence/jpeg_search.dd 2>/dev/null || true

    mkdir -p /tmp/evidence_jpgs

    # Download real photographs from picsum.photos (Lorem Picsum - free stock photos)
    # Each URL returns a real photograph at the specified resolution
    echo "  Downloading real photographs from picsum.photos..."
    wget --timeout=15 -q -O /tmp/evidence_jpgs/photo_landscape.jpg "https://picsum.photos/seed/forensic1/640/480.jpg" 2>/dev/null || true
    wget --timeout=15 -q -O /tmp/evidence_jpgs/IMG_20240115_142305.jpg "https://picsum.photos/seed/forensic2/800/600.jpg" 2>/dev/null || true
    wget --timeout=15 -q -O /tmp/evidence_jpgs/screenshot_desktop.jpg "https://picsum.photos/seed/forensic3/1024/768.jpg" 2>/dev/null || true
    wget --timeout=15 -q -O /tmp/evidence_jpgs/receipt_scan_01.jpg "https://picsum.photos/seed/forensic4/400/600.jpg" 2>/dev/null || true
    wget --timeout=15 -q -O /tmp/evidence_jpgs/vacation_sunset.jpg "https://picsum.photos/seed/forensic5/640/480.jpg" 2>/dev/null || true

    # Verify at least some photos downloaded (should be real JPEGs, >5KB each)
    PHOTO_COUNT=0
    for f in /tmp/evidence_jpgs/*.jpg; do
        if [ -s "$f" ] && [ "$(stat -c%s "$f")" -gt 5000 ]; then
            PHOTO_COUNT=$((PHOTO_COUNT + 1))
            echo "  Downloaded: $(basename "$f") ($(stat -c%s "$f") bytes)"
        else
            rm -f "$f" 2>/dev/null
        fi
    done

    # If photo downloads failed, generate gradient images with Pillow (not random noise)
    if [ "$PHOTO_COUNT" -lt 3 ]; then
        echo "  Photo downloads insufficient ($PHOTO_COUNT). Generating gradient images..."
        python3 -c "
from PIL import Image, ImageDraw, ImageFont
import os, math

# Generate images with realistic gradients and patterns (not random noise)
scenes = [
    ('photo_landscape.jpg', (640, 480), [(34,139,34), (135,206,235)]),   # green-to-sky gradient
    ('IMG_20240115_142305.jpg', (800, 600), [(255,140,0), (255,69,0)]),  # sunset gradient
    ('screenshot_desktop.jpg', (1024, 768), [(50,50,80), (100,100,140)]), # dark blue desktop
    ('receipt_scan_01.jpg', (400, 600), [(245,245,220), (210,210,190)]),  # beige paper
    ('vacation_sunset.jpg', (640, 480), [(255,94,77), (255,154,0)]),     # warm sunset
]
for fname, size, (c1, c2) in scenes:
    img = Image.new('RGB', size)
    draw = ImageDraw.Draw(img)
    for y in range(size[1]):
        t = y / size[1]
        r = int(c1[0] * (1-t) + c2[0] * t)
        g = int(c1[1] * (1-t) + c2[1] * t)
        b = int(c1[2] * (1-t) + c2[2] * t)
        draw.line([(0, y), (size[0], y)], fill=(r, g, b))
    # Add some variation with circles to make it look more photo-like
    for i in range(8):
        cx = int(size[0] * (0.1 + 0.8 * (i / 8.0)))
        cy = int(size[1] * (0.3 + 0.4 * math.sin(i * 0.8)))
        radius = 20 + i * 5
        opacity = 30 + i * 10
        draw.ellipse([cx-radius, cy-radius, cx+radius, cy+radius],
                     fill=(min(255, c1[0]+opacity), min(255, c1[1]+opacity), min(255, c1[2]+opacity)))
    path = os.path.join('/tmp/evidence_jpgs', fname)
    if not os.path.exists(path):
        img.save(path, 'JPEG', quality=85)
        print(f'  Generated gradient: {fname} ({os.path.getsize(path)} bytes)')
" 2>/dev/null || true
    fi

    # Copy files into the FAT image using mcopy (no loop mount needed)
    if command -v mcopy >/dev/null 2>&1; then
        for f in /tmp/evidence_jpgs/*; do
            [ -f "$f" ] && mcopy -i /home/ga/evidence/jpeg_search.dd "$f" "::$(basename "$f")" 2>/dev/null || true
        done
    else
        mkdir -p /tmp/ev_jpg
        if mount -o loop /home/ga/evidence/jpeg_search.dd /tmp/ev_jpg 2>/dev/null; then
            cp /tmp/evidence_jpgs/* /tmp/ev_jpg/ 2>/dev/null || true
            sync
            umount /tmp/ev_jpg 2>/dev/null || true
        fi
        rmdir /tmp/ev_jpg 2>/dev/null || true
    fi
    rm -rf /tmp/evidence_jpgs
    echo "  Local jpeg_search.dd: $(stat -c%s /home/ga/evidence/jpeg_search.dd 2>/dev/null) bytes"
fi


# ============================================================
# Download DFTT #11: Keyword Search test image (real forensic test data)
# Source: https://dftt.sourceforge.net/test11/index.html
# Contains: NTFS filesystem with text files containing forensic keywords
# for testing keyword search functionality of forensic tools.
# ============================================================
echo "Downloading DFTT #11 Keyword Search test image..."
KW_OK=false
for attempt in 1 2 3; do
    echo "  Attempt $attempt..."
    wget --timeout=60 --tries=1 -q -O /tmp/11-kombi.zip \
        "https://prdownloads.sourceforge.net/dftt/11-kombi.zip?download" 2>&1 || true
    if [ -s /tmp/11-kombi.zip ]; then
        if file /tmp/11-kombi.zip 2>/dev/null | grep -qi "zip"; then
            echo "  ZIP downloaded ($(stat -c%s /tmp/11-kombi.zip) bytes)"
            cd /tmp && unzip -o -q 11-kombi.zip 2>&1 || true
            EXTRACTED=$(find /tmp -maxdepth 3 \( -name "*kombi*ntfs*.dd" -o -name "*kombi*.dd" -o -name "*keyword*.dd" \) -type f 2>/dev/null | head -1)
            if [ -s "$EXTRACTED" ]; then
                mv "$EXTRACTED" /home/ga/evidence/keyword_search.dd
                echo "  DFTT keyword_search.dd: $(stat -c%s /home/ga/evidence/keyword_search.dd) bytes"
                KW_OK=true
            else
                echo "  ZIP extracted but keyword dd not found, listing /tmp:"
                ls /tmp/*.dd /tmp/**/*.dd 2>/dev/null || true
            fi
            rm -rf /tmp/11-kombi.zip /tmp/11-kombi 2>/dev/null || true
            [ "$KW_OK" = true ] && break
        fi
    fi
    rm -f /tmp/11-kombi.zip
    sleep 3
done

# Fallback: use ntfs_undel.dd as keyword_search.dd (symlink, works for basic testing)
if [ "$KW_OK" = false ]; then
    echo "  DFTT #11 download failed. Linking ntfs_undel.dd as keyword_search.dd..."
    ln -sf /home/ga/evidence/ntfs_undel.dd /home/ga/evidence/keyword_search.dd 2>/dev/null || \
    cp /home/ga/evidence/ntfs_undel.dd /home/ga/evidence/keyword_search.dd 2>/dev/null || true
    echo "  keyword_search.dd: $(stat -c%s /home/ga/evidence/keyword_search.dd 2>/dev/null) bytes"
fi

chown -R ga:ga /home/ga/evidence/ 2>/dev/null || true

# ============================================================
# Step 7: Final verification
# ============================================================
echo "=== Final verification ==="
echo "Java: $(java -version 2>&1 | head -1)"
[ -x /usr/local/bin/autopsy ] && echo "Autopsy: OK" || echo "Autopsy: NOT FOUND"

# Check TSK
for tool in fls icat mmls img_stat; do
    command -v "$tool" >/dev/null 2>&1 && echo "TSK $tool: OK" || echo "TSK $tool: not found"
done

# Check JNI
find / -name "libtsk_jni*" 2>/dev/null | head -3

echo "Evidence files:"
ls -la /home/ga/evidence/ 2>/dev/null || echo "No evidence dir"

echo "Disk: $(df -h / 2>/dev/null | tail -1)"
echo "Mem: $(free -h 2>/dev/null | grep Mem)"

echo "=== Autopsy installation complete ==="
