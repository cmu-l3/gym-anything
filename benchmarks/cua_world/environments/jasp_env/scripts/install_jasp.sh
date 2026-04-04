#!/bin/bash
set -e

echo "=== Installing JASP Statistics and dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

echo "Installing system dependencies and GUI automation tools..."
apt-get install -y \
    wget \
    curl \
    ca-certificates \
    software-properties-common \
    apt-transport-https \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    python3-pip \
    gnupg \
    xz-utils

echo "Installing Flatpak..."
apt-get install -y flatpak

echo "Adding Flathub repository..."
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

echo "Installing JASP via Flatpak (system-wide)..."
# This downloads JASP and its KDE Platform runtime (~2-3 GB total)
# Retries up to 3 times in case of transient network issues
for attempt in 1 2 3; do
    echo "Attempt $attempt: flatpak install JASP..."
    if flatpak install --system --noninteractive flathub org.jaspstats.JASP 2>&1; then
        echo "JASP flatpak installed successfully on attempt $attempt"
        break
    fi
    if [ $attempt -eq 3 ]; then
        echo "ERROR: Failed to install JASP after 3 attempts"
        exit 1
    fi
    echo "Attempt $attempt failed, retrying in 10s..."
    sleep 10
done

echo "Verifying JASP installation..."
flatpak list --system | grep -i jasp || { echo "ERROR: JASP not found in flatpak list"; exit 1; }

echo "=== Downloading real JASP example datasets from official JASP GitHub ==="
# These datasets are from published research papers, used in JASP's official documentation.
# Source: https://github.com/jasp-stats/jasp-desktop/tree/master/Resources/Data%20Sets/

mkdir -p /opt/jasp_datasets

# 1. Sleep dataset (Gosset/Student 1908) - for descriptive statistics
# Classic dataset comparing sleep durations in two groups
wget -q -O "/opt/jasp_datasets/Sleep.csv" \
    "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/1.%20Descriptives/Sleep.csv"

SLEEP_SIZE=$(stat -c%s /opt/jasp_datasets/Sleep.csv 2>/dev/null || echo 0)
if [ "$SLEEP_SIZE" -lt 100 ]; then
    echo "ERROR: Sleep.csv download failed (size: ${SLEEP_SIZE} bytes)"
    exit 1
fi
echo "Sleep.csv downloaded: ${SLEEP_SIZE} bytes"

# 2. Invisibility Cloak dataset (Field 2013) - for independent samples t-test
# Real dataset from field experiment: mischief with/without invisibility cloak
wget -q -O "/opt/jasp_datasets/Invisibility Cloak.csv" \
    "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/2.%20T-Tests/Invisibility%20Cloak.csv"

CLOAK_SIZE=$(stat -c%s "/opt/jasp_datasets/Invisibility Cloak.csv" 2>/dev/null || echo 0)
if [ "$CLOAK_SIZE" -lt 100 ]; then
    echo "ERROR: Invisibility Cloak.csv download failed (size: ${CLOAK_SIZE} bytes)"
    exit 1
fi
echo "Invisibility Cloak.csv downloaded: ${CLOAK_SIZE} bytes"

# 3. Viagra dataset (Field 2013) - for one-way ANOVA
# Real pharmacological study: effect of Viagra dose on libido
wget -q -O "/opt/jasp_datasets/Viagra.csv" \
    "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/3.%20ANOVA/Viagra.csv"

VIAGRA_SIZE=$(stat -c%s /opt/jasp_datasets/Viagra.csv 2>/dev/null || echo 0)
if [ "$VIAGRA_SIZE" -lt 100 ]; then
    echo "ERROR: Viagra.csv download failed (size: ${VIAGRA_SIZE} bytes)"
    exit 1
fi
echo "Viagra.csv downloaded: ${VIAGRA_SIZE} bytes"

# 4. Exam Anxiety dataset (Field 2013) - for linear regression
# Real dataset: exam performance predicted by revision time and anxiety
wget -q -O "/opt/jasp_datasets/Exam Anxiety.csv" \
    "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/4.%20Regression/Exam%20Anxiety.csv"

EXAM_SIZE=$(stat -c%s "/opt/jasp_datasets/Exam Anxiety.csv" 2>/dev/null || echo 0)
if [ "$EXAM_SIZE" -lt 100 ]; then
    echo "ERROR: Exam Anxiety.csv download failed (size: ${EXAM_SIZE} bytes)"
    exit 1
fi
echo "Exam Anxiety.csv downloaded: ${EXAM_SIZE} bytes"

# 5. Big Five Personality Traits dataset (real NEO personality research data) - for correlations
wget -q -O "/opt/jasp_datasets/Big Five Personality Traits.csv" \
    "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/4.%20Regression/Big%20Five%20Personality%20Traits.csv"

BIG5_SIZE=$(stat -c%s "/opt/jasp_datasets/Big Five Personality Traits.csv" 2>/dev/null || echo 0)
if [ "$BIG5_SIZE" -lt 100 ]; then
    echo "ERROR: Big Five Personality Traits.csv download failed (size: ${BIG5_SIZE} bytes)"
    exit 1
fi
echo "Big Five Personality Traits.csv downloaded: ${BIG5_SIZE} bytes"

# 6. Tooth Growth dataset (Crampton 1947) - for factorial ANOVA
# Real dataset: effect of vitamin C on tooth growth in guinea pigs (60 obs)
wget -q -O "/opt/jasp_datasets/Tooth Growth.csv" \
    "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/3.%20ANOVA/Tooth%20Growth.csv"

TOOTH_SIZE=$(stat -c%s "/opt/jasp_datasets/Tooth Growth.csv" 2>/dev/null || echo 0)
if [ "$TOOTH_SIZE" -lt 100 ]; then
    echo "ERROR: Tooth Growth.csv download failed (size: ${TOOTH_SIZE} bytes)"
    exit 1
fi
echo "Tooth Growth.csv downloaded: ${TOOTH_SIZE} bytes"

chmod -R 755 /opt/jasp_datasets
echo "All datasets downloaded and verified."

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== JASP installation complete ==="
