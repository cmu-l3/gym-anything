#!/bin/bash
set -e

echo "=== Installing OpenBCI GUI ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install system dependencies
echo "Installing system dependencies..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    scrot \
    imagemagick \
    unzip \
    tar \
    curl \
    wget \
    libxrender1 \
    libxtst6 \
    libxi6 \
    libxrandr2 \
    libgl1 \
    libglu1-mesa \
    libasound2 \
    fonts-dejavu-core

# Install Python tools for EEG data conversion
echo "Installing Python tools..."
apt-get install -y \
    python3-pip \
    python3-numpy \
    python3-scipy

# Install pyEDFlib for EDF file reading (lightweight, no heavy deps)
pip3 install --no-cache-dir --break-system-packages pyEDFlib 2>/dev/null || \
    pip3 install --no-cache-dir pyEDFlib 2>/dev/null || \
    echo "WARNING: Could not install pyEDFlib"

# ============================================================
# Download OpenBCI GUI v5.2.2 (latest stable Linux release)
# ============================================================
echo "Downloading OpenBCI GUI v5.2.2..."
OPENBCI_DIR="/opt/openbci_gui"
mkdir -p "$OPENBCI_DIR"

cd /tmp

PRIMARY_URL="https://github.com/OpenBCI/OpenBCI_GUI/releases/download/v5.2.2/openbcigui_v5.2.2_2023-08-21_16-14-34_linux64.zip"
FALLBACK_URL="https://github.com/OpenBCI/OpenBCI_GUI/releases/download/v5.2.1/openbcigui_v5.2.1_2023-07-11_17-09-27_linux64.zip"

wget --timeout=300 --tries=3 -q "$PRIMARY_URL" -O openbci_gui.zip 2>&1 || {
    echo "Primary URL failed, trying fallback..."
    wget --timeout=300 --tries=3 -q "$FALLBACK_URL" -O openbci_gui.zip 2>&1 || {
        echo "ERROR: Could not download OpenBCI GUI"
        exit 1
    }
}

if [ -f openbci_gui.zip ] && [ -s openbci_gui.zip ]; then
    echo "Extracting OpenBCI GUI..."
    unzip -qo openbci_gui.zip -d "$OPENBCI_DIR" 2>&1
    rm -f openbci_gui.zip
    echo "Extraction complete. Contents of $OPENBCI_DIR:"
    ls -la "$OPENBCI_DIR/"
else
    echo "ERROR: Download file is empty or missing"
    exit 1
fi

# Find the actual executable
echo "Locating OpenBCI GUI executable..."
OPENBCI_EXEC=""
for path in \
    "$OPENBCI_DIR/OpenBCI_GUI" \
    "$OPENBCI_DIR/OpenBCI_GUI/OpenBCI_GUI" \
    "$OPENBCI_DIR/openbci_gui/OpenBCI_GUI" \
    $(find "$OPENBCI_DIR" -maxdepth 3 -name "OpenBCI_GUI" -type f 2>/dev/null | head -1); do
    if [ -f "$path" ] && [ ! -d "$path" ]; then
        OPENBCI_EXEC="$path"
        echo "Found executable: $OPENBCI_EXEC"
        break
    fi
done

if [ -z "$OPENBCI_EXEC" ]; then
    echo "WARNING: Could not find 'OpenBCI_GUI' binary, searching deeper..."
    OPENBCI_EXEC=$(find "$OPENBCI_DIR" -name "OpenBCI_GUI" -type f 2>/dev/null | head -1)
    # Also check for shell scripts
    if [ -z "$OPENBCI_EXEC" ]; then
        OPENBCI_EXEC=$(find "$OPENBCI_DIR" -name "*.sh" -type f 2>/dev/null | grep -i openbci | head -1)
    fi
    echo "Found: $OPENBCI_EXEC"
fi

if [ -n "$OPENBCI_EXEC" ]; then
    chmod +x "$OPENBCI_EXEC"
    OPENBCI_BASE_DIR=$(dirname "$OPENBCI_EXEC")

    # Create /usr/local/bin wrapper
    cat > /usr/local/bin/openbci_gui << WRAPPER_EOF
#!/bin/bash
# OpenBCI GUI launcher wrapper
export DISPLAY=\${DISPLAY:-:1}
cd "$OPENBCI_BASE_DIR" || exit 1
exec "$OPENBCI_EXEC" "\$@"
WRAPPER_EOF
    chmod +x /usr/local/bin/openbci_gui
    echo "Created launcher at /usr/local/bin/openbci_gui"
    echo "  Base dir: $OPENBCI_BASE_DIR"
    echo "  Executable: $OPENBCI_EXEC"

    # Save locations for setup script to use
    echo "$OPENBCI_EXEC" > /opt/openbci_exec_path.txt
    echo "$OPENBCI_BASE_DIR" > /opt/openbci_base_dir.txt
else
    echo "ERROR: Could not find OpenBCI GUI executable"
    find "$OPENBCI_DIR" -type f | head -20
    exit 1
fi

# Set permissions and ownership so ga user can write to the app dir
# (Processing apps write config/settings into their own directory)
chmod -R 755 "$OPENBCI_DIR"
chown -R ga:ga "$OPENBCI_DIR"

# ============================================================
# Obtain EEG data for playback tasks
# Primary: use pre-built files from /workspace/data/ (shipped in repo, no network needed)
# Fallback: download from PhysioNet and convert from EDF format
# Citation: Schalk et al. (2004), Goldberger et al. (2000)
# License: PhysioNet Credentialed Health Data License — publicly available
# ============================================================
OPENBCI_DATA_DIR="/opt/openbci_data"
mkdir -p "$OPENBCI_DATA_DIR"

EYES_OPEN_DEST="${OPENBCI_DATA_DIR}/OpenBCI-EEG-S001-EyesOpen.txt"
MOTOR_DEST="${OPENBCI_DATA_DIR}/OpenBCI-EEG-S001-MotorImagery.txt"

# Check for pre-built files in /workspace/data/ (mounted from repo data/ directory)
LOCAL_EYES_OPEN=""
for candidate in \
    "/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt" \
    "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt"; do
    if [ -f "$candidate" ] && [ "$(wc -c < "$candidate")" -gt 10000 ]; then
        LOCAL_EYES_OPEN="$candidate"
        break
    fi
done

if [ -n "$LOCAL_EYES_OPEN" ]; then
    echo "Using local EEG file (eyes open): $LOCAL_EYES_OPEN"
    cp "$LOCAL_EYES_OPEN" "$EYES_OPEN_DEST"
    echo "Copied to $EYES_OPEN_DEST"
else
    echo "Local EEG file not found, downloading from PhysioNet..."
    PHYSIONET_BASE="https://physionet.org/files/eegmmidb/1.0.0"
    EDF_FILE="S001R01.edf"
    wget --timeout=120 --tries=3 -q \
        "${PHYSIONET_BASE}/S001/${EDF_FILE}" \
        -O "${OPENBCI_DATA_DIR}/${EDF_FILE}" 2>&1 || {
        echo "WARNING: Could not download PhysioNet EEG data. Playback tasks will not be available."
    }
fi

# Motor imagery file
if [ -f "/workspace/data/OpenBCI-EEG-S001-MotorImagery.txt" ] && \
   [ "$(wc -c < /workspace/data/OpenBCI-EEG-S001-MotorImagery.txt)" -gt 10000 ]; then
    echo "Using local EEG file (motor imagery)"
    cp /workspace/data/OpenBCI-EEG-S001-MotorImagery.txt "$MOTOR_DEST"
else
    echo "Local motor imagery file not found, downloading from PhysioNet..."
    PHYSIONET_BASE="https://physionet.org/files/eegmmidb/1.0.0"
    EDF_FILE2="S001R04.edf"
    wget --timeout=120 --tries=3 -q \
        "${PHYSIONET_BASE}/S001/${EDF_FILE2}" \
        -O "${OPENBCI_DATA_DIR}/${EDF_FILE2}" 2>&1 || {
        echo "WARNING: Could not download PhysioNet EEG data R04"
    }
fi

# ============================================================
# Convert EDF data to OpenBCI CSV format
# ============================================================
echo "Converting EEG data to OpenBCI CSV format..."

cat > /opt/convert_eeg_to_openbci.py << 'PYEOF'
#!/usr/bin/env python3
"""
Convert PhysioNet EEG Motor Movement/Imagery Dataset EDF files
to OpenBCI-compatible CSV playback format.

Dataset: https://physionet.org/content/eegmmidb/1.0.0/
Subject: S001, Run 01 (eyes open baseline) and Run 04 (motor imagery)
License: PhysioNet Credentialed Health Data License
"""

import sys
import os
import numpy as np
from datetime import datetime

def convert_edf_to_openbci_csv(edf_path, output_path, target_channels=None, target_srate=250):
    """Convert EDF file to OpenBCI v5 CSV format."""
    try:
        import pyedflib
    except ImportError:
        print("ERROR: pyedflib not installed. Run: pip3 install pyEDFlib")
        return False

    print(f"Reading EDF file: {edf_path}")
    f = pyedflib.EdfReader(edf_path)

    n_signals = f.signals_in_file
    signal_labels = f.getSignalLabels()
    sample_frequencies = [f.getSampleFrequency(i) for i in range(n_signals)]
    # Strip whitespace/dots from channel names
    clean_labels = [lbl.strip().rstrip('.').upper() for lbl in signal_labels]

    print(f"Available channels: {clean_labels}")
    print(f"Sample frequencies: {list(set(sample_frequencies))}")

    # Target 8 channels from PhysioNet EEGMMI (64-ch, 160 Hz)
    # Using channels that span the full scalp: frontal, central, parietal, occipital
    if target_channels is None:
        # Priority order: try to find these channels
        preferred = ['AF3', 'AF4', 'C3', 'C4', 'P7', 'P8', 'O1', 'O2']
        fallback1 = ['F3', 'F4', 'C3', 'C4', 'P7', 'P8', 'O1', 'O2']
        fallback2 = ['FC5', 'FC6', 'C3', 'C4', 'CP5', 'CP6', 'O1', 'O2']

        for candidate_set in [preferred, fallback1, fallback2]:
            indices = []
            names = []
            for ch in candidate_set:
                found = False
                for i, lbl in enumerate(clean_labels):
                    if lbl == ch.upper() or lbl == ch.upper() + '.' or lbl.rstrip('.') == ch.upper():
                        indices.append(i)
                        names.append(ch)
                        found = True
                        break
                if not found:
                    break
            if len(indices) == len(candidate_set):
                target_channels = {'indices': indices, 'names': names}
                print(f"Using channels: {names}")
                break

    if target_channels is None:
        # Last resort: take the first 8 EEG channels (excluding annotations)
        indices = []
        names = []
        for i, lbl in enumerate(clean_labels):
            if 'EEG' not in lbl.upper() and lbl.upper() not in ['ANNOTATIONS']:
                # This is probably an EEG channel with just a name
                if len(indices) < 8:
                    indices.append(i)
                    names.append(lbl.strip('.'))
        if len(indices) < 8:
            indices = list(range(min(8, n_signals - 1)))
            names = [clean_labels[i] for i in indices]
        target_channels = {'indices': indices, 'names': names}
        print(f"Using fallback channels: {names}")

    ch_indices = target_channels['indices']
    ch_names = target_channels['names']
    openbci_names = ['Fp1', 'Fp2', 'C3', 'C4', 'P7', 'P8', 'O1', 'O2']

    # Read signal data
    print(f"Reading signal data from {len(ch_indices)} channels...")
    orig_srate = sample_frequencies[ch_indices[0]]
    print(f"Original sample rate: {orig_srate} Hz")

    signals = []
    for idx in ch_indices:
        sig = f.readSignal(idx)
        # Convert to microvolts if needed (EEGMMI data is in microvolts)
        signals.append(sig)

    f._close()
    del f

    signals = np.array(signals)  # shape: (n_channels, n_samples)
    n_samples_orig = signals.shape[1]
    print(f"Original samples: {n_samples_orig} ({n_samples_orig/orig_srate:.1f}s)")

    # Resample to target_srate (250 Hz)
    if orig_srate != target_srate:
        print(f"Resampling from {orig_srate} Hz to {target_srate} Hz...")
        from scipy.signal import resample
        n_samples_new = int(n_samples_orig * target_srate / orig_srate)
        signals = resample(signals, n_samples_new, axis=1)
        print(f"Resampled to {signals.shape[1]} samples")
    else:
        n_samples_new = n_samples_orig

    # Limit to 120 seconds (sufficient for tasks)
    max_samples = min(n_samples_new, target_srate * 120)
    signals = signals[:, :max_samples]
    n_final = signals.shape[1]
    print(f"Final samples: {n_final} ({n_final/target_srate:.1f}s)")

    # Write OpenBCI v5 CSV format
    print(f"Writing OpenBCI CSV to: {output_path}")
    start_ts = 1705312800.0  # 2024-01-15 10:00:00 UTC

    with open(output_path, 'w') as out:
        # Header comments (OpenBCI format)
        out.write('%OpenBCI Raw EEG Data\n')
        out.write(f'%Number of channels = 8\n')
        out.write(f'%Sample Rate = {target_srate} Hz\n')
        out.write('%Board = OpenBCI_V3\n')
        out.write(f'%Channel Order = {", ".join(openbci_names)}\n')
        out.write('%Source = PhysioNet EEG Motor Movement/Imagery Dataset (eegmmidb 1.0.0)\n')
        out.write('%Subject = S001\n')

        # Column headers (with leading space to match OpenBCI format)
        headers = [' Sample Index'] + [f' EXG Channel {i}' for i in range(8)] + \
                  [' Accel Channel 0', ' Accel Channel 1', ' Accel Channel 2'] + \
                  [' Other'] * 7 + [' Timestamp (Formatted)', ' Timestamp (Unix)']
        out.write(','.join(headers) + '\n')

        # Data rows
        for i in range(n_final):
            sample_idx = i % 256
            ch_vals = ','.join([f' {v:.4f}' for v in signals[:, i]])
            accel = ' 0.0000, 0.0000, 0.0000'
            others = ', 0.0000' * 7
            ts_unix = start_ts + i / target_srate
            ts_dt = datetime.utcfromtimestamp(ts_unix)
            ts_formatted = ts_dt.strftime(' %Y-%m-%d %H:%M:%S.') + f'{ts_dt.microsecond//1000:03d}'
            out.write(f'{sample_idx},{ch_vals},{accel}{others},{ts_formatted}, {ts_unix:.3f}\n')

    print(f"Conversion complete! {n_final} samples written.")
    return True


if __name__ == '__main__':
    data_dir = '/opt/openbci_data'
    output_dir = '/opt/openbci_data'
    os.makedirs(output_dir, exist_ok=True)

    # Convert Run 01 (eyes open baseline)
    edf1 = os.path.join(data_dir, 'S001R01.edf')
    if os.path.exists(edf1) and os.path.getsize(edf1) > 1000:
        success = convert_edf_to_openbci_csv(
            edf1,
            os.path.join(output_dir, 'OpenBCI-EEG-S001-EyesOpen.txt')
        )
        if success:
            print("SUCCESS: Converted S001R01 (eyes open baseline)")
    else:
        print(f"WARNING: {edf1} not found or empty, skipping")

    # Convert Run 04 (motor imagery)
    edf2 = os.path.join(data_dir, 'S001R04.edf')
    if os.path.exists(edf2) and os.path.getsize(edf2) > 1000:
        success = convert_edf_to_openbci_csv(
            edf2,
            os.path.join(output_dir, 'OpenBCI-EEG-S001-MotorImagery.txt')
        )
        if success:
            print("SUCCESS: Converted S001R04 (motor imagery)")
    else:
        print(f"WARNING: {edf2} not found or empty, skipping")
PYEOF
chmod +x /opt/convert_eeg_to_openbci.py

# Run conversion
python3 /opt/convert_eeg_to_openbci.py 2>&1 || echo "WARNING: EEG conversion had issues"

# Check if conversion succeeded
if [ -f /opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt ]; then
    SIZE=$(wc -l < /opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt)
    echo "EEG playback file created: ${SIZE} lines"
else
    echo "WARNING: EEG playback file not created (playback tasks will not function)"
fi

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== OpenBCI GUI Installation Summary ==="
echo "OpenBCI GUI executable: $(cat /opt/openbci_exec_path.txt 2>/dev/null || echo 'not found')"
echo "OpenBCI GUI base dir: $(cat /opt/openbci_base_dir.txt 2>/dev/null || echo 'not found')"
echo "EEG data dir: /opt/openbci_data/"
ls -la /opt/openbci_data/ 2>/dev/null || echo "(no EEG data)"
echo ""
echo "=== OpenBCI GUI installation complete ==="
