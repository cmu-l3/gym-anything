#!/bin/bash
set -e

echo "=== Installing KNIME Analytics Platform ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install dependencies: GTK3, fonts, X11 tools, general utilities
apt-get install -y \
    libgtk-3-0 \
    libswt-gtk-4-jni \
    libwebkit2gtk-4.0-37 \
    fonts-dejavu \
    fonts-liberation \
    fontconfig \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot \
    imagemagick \
    python3-pip \
    curl \
    wget \
    unzip \
    ca-certificates \
    || echo "Some optional packages may not be available, continuing..."

# -------------------------------------------------------
# Download and install KNIME Analytics Platform
# -------------------------------------------------------
echo "=== Downloading KNIME Analytics Platform ==="

KNIME_INSTALL_DIR="/opt/knime"
KNIME_TARBALL="/tmp/knime.tar.gz"

# Try multiple download URLs with fallbacks
download_knime() {
    local urls=(
        "https://download.knime.org/analytics-platform/linux/knime-latest-linux.gtk.x86_64.tar.gz"
        "https://download.knime.org/analytics-platform/linux/knime_5.4.2.linux.gtk.x86_64.tar.gz"
        "https://download.knime.org/analytics-platform/linux/knime_5.3.3.linux.gtk.x86_64.tar.gz"
        "https://download.knime.org/analytics-platform/linux/knime_5.3.2.linux.gtk.x86_64.tar.gz"
        "https://download.knime.org/analytics-platform/linux/knime_5.2.6.linux.gtk.x86_64.tar.gz"
    )

    for url in "${urls[@]}"; do
        echo "Trying: $url"
        if wget -q --timeout=120 --tries=2 -O "$KNIME_TARBALL" "$url"; then
            # Verify it's a valid gzip file
            if gzip -t "$KNIME_TARBALL" 2>/dev/null; then
                echo "Successfully downloaded KNIME from: $url"
                return 0
            else
                echo "Downloaded file is not valid gzip, trying next URL..."
                rm -f "$KNIME_TARBALL"
            fi
        else
            echo "Failed to download from: $url"
            rm -f "$KNIME_TARBALL"
        fi
    done

    echo "ERROR: Failed to download KNIME from all URLs"
    return 1
}

download_knime

# Extract KNIME
echo "=== Extracting KNIME ==="
mkdir -p "$KNIME_INSTALL_DIR"
tar -xzf "$KNIME_TARBALL" -C /opt/

# Find the extracted directory (name varies by version)
KNIME_EXTRACTED=$(find /opt -maxdepth 1 -name 'knime_*' -type d | head -1)
if [ -z "$KNIME_EXTRACTED" ]; then
    KNIME_EXTRACTED=$(find /opt -maxdepth 1 -name 'knime*' -type d | grep -v "^/opt/knime$" | head -1)
fi

if [ -z "$KNIME_EXTRACTED" ] || [ ! -f "$KNIME_EXTRACTED/knime" ]; then
    echo "ERROR: Could not find extracted KNIME directory"
    ls -la /opt/
    exit 1
fi

# Move to standard location if needed
if [ "$KNIME_EXTRACTED" != "$KNIME_INSTALL_DIR" ]; then
    rm -rf "$KNIME_INSTALL_DIR"
    mv "$KNIME_EXTRACTED" "$KNIME_INSTALL_DIR"
fi

echo "KNIME installed at: $KNIME_INSTALL_DIR"

# Create symlink for easy access
ln -sf "$KNIME_INSTALL_DIR/knime" /usr/local/bin/knime

# Configure JVM memory in knime.ini
# Set heap to 4GB (appropriate for 8GB VM)
if [ -f "$KNIME_INSTALL_DIR/knime.ini" ]; then
    sed -i 's/-Xmx[0-9]*[mMgG]/-Xmx4096m/' "$KNIME_INSTALL_DIR/knime.ini"
    echo "Configured JVM heap to 4096m"
fi

# Set ownership so ga user can run KNIME
chown -R ga:ga "$KNIME_INSTALL_DIR"

# Clean up tarball
rm -f "$KNIME_TARBALL"

# -------------------------------------------------------
# Download real datasets
# -------------------------------------------------------
echo "=== Downloading real datasets ==="

DATA_DIR="/home/ga/Documents/data"
mkdir -p "$DATA_DIR"

# Download Titanic dataset (real historical data from Kaggle/DataScienceDojo)
echo "Downloading Titanic dataset..."
TITANIC_URLS=(
    "https://raw.githubusercontent.com/datasciencedojo/datasets/master/titanic.csv"
    "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/titanic.csv"
)
TITANIC_DOWNLOADED=false
for url in "${TITANIC_URLS[@]}"; do
    if wget -q --timeout=30 --tries=2 -O "$DATA_DIR/titanic.csv" "$url"; then
        if [ -s "$DATA_DIR/titanic.csv" ]; then
            echo "Titanic dataset downloaded from: $url"
            TITANIC_DOWNLOADED=true
            break
        fi
    fi
done

# If online download fails, copy from mounted data directory
if [ "$TITANIC_DOWNLOADED" = false ] && [ -f /workspace/data/titanic.csv ]; then
    cp /workspace/data/titanic.csv "$DATA_DIR/titanic.csv"
    echo "Titanic dataset copied from mounted data"
    TITANIC_DOWNLOADED=true
fi

if [ "$TITANIC_DOWNLOADED" = false ]; then
    echo "WARNING: Could not download Titanic dataset"
fi

# Download Iris dataset (Fisher's real botanical measurements from UCI ML Repository)
echo "Downloading Iris dataset..."
IRIS_URLS=(
    "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv"
    "https://raw.githubusercontent.com/pandas-dev/pandas/main/pandas/tests/io/data/csv/iris.csv"
)
IRIS_DOWNLOADED=false
for url in "${IRIS_URLS[@]}"; do
    if wget -q --timeout=30 --tries=2 -O "$DATA_DIR/iris.csv" "$url"; then
        if [ -s "$DATA_DIR/iris.csv" ]; then
            echo "Iris dataset downloaded from: $url"
            IRIS_DOWNLOADED=true
            break
        fi
    fi
done

# If online download fails but UCI raw data is available, add headers
if [ "$IRIS_DOWNLOADED" = false ]; then
    IRIS_RAW_URL="https://archive.ics.uci.edu/ml/machine-learning-databases/iris/iris.data"
    if wget -q --timeout=30 --tries=2 -O /tmp/iris_raw.csv "$IRIS_RAW_URL"; then
        echo "sepal_length,sepal_width,petal_length,petal_width,species" > "$DATA_DIR/iris.csv"
        cat /tmp/iris_raw.csv >> "$DATA_DIR/iris.csv"
        rm -f /tmp/iris_raw.csv
        echo "Iris dataset downloaded from UCI (with headers added)"
        IRIS_DOWNLOADED=true
    fi
fi

# Fallback: copy from mounted data directory
if [ "$IRIS_DOWNLOADED" = false ] && [ -f /workspace/data/iris.csv ]; then
    cp /workspace/data/iris.csv "$DATA_DIR/iris.csv"
    echo "Iris dataset copied from mounted data"
    IRIS_DOWNLOADED=true
fi

if [ "$IRIS_DOWNLOADED" = false ]; then
    echo "WARNING: Could not download Iris dataset"
fi

# Set ownership
chown -R ga:ga "$DATA_DIR"

# -------------------------------------------------------
# Cleanup
# -------------------------------------------------------
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== KNIME Analytics Platform installation complete ==="
echo "KNIME binary: $KNIME_INSTALL_DIR/knime"
echo "Datasets: $DATA_DIR/"
ls -la "$DATA_DIR/"
