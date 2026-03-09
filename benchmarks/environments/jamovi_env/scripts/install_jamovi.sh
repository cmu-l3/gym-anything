#!/bin/bash
set -e

echo "=== Installing Jamovi Statistics and dependencies ==="

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

echo "Installing Jamovi via Flatpak (system-wide)..."
# Jamovi is an Electron-based statistical software available only via Flatpak on Linux.
# First attempt caches runtimes; second attempt installs the app itself.
for attempt in 1 2 3; do
    echo "Attempt $attempt: flatpak install Jamovi..."
    if flatpak install --system --noninteractive flathub org.jamovi.jamovi 2>&1; then
        echo "Jamovi flatpak installed successfully on attempt $attempt"
        break
    fi
    if [ $attempt -eq 3 ]; then
        echo "ERROR: Failed to install Jamovi after 3 attempts"
        exit 1
    fi
    echo "Attempt $attempt failed, retrying in 10s..."
    sleep 10
done

echo "Verifying Jamovi installation..."
flatpak list --system | grep -i jamovi || { echo "ERROR: Jamovi not found in flatpak list"; exit 1; }

echo "=== Downloading real research datasets ==="
# These datasets are from published research papers, used in standard statistical textbooks.
# Source: https://github.com/jasp-stats/jasp-desktop/tree/master/Resources/Data%20Sets/
# They are available as open data accompanying the textbook "Discovering Statistics Using R" (Field, 2013).

mkdir -p /opt/jamovi_datasets

# 1. Sleep dataset (Student/Gosset 1908) — classic two-group sleep study
#    Variables: extra (hours of extra sleep), group (1 or 2)
wget -q -O "/opt/jamovi_datasets/Sleep.csv" \
    "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/1.%20Descriptives/Sleep.csv"

SLEEP_SIZE=$(stat -c%s /opt/jamovi_datasets/Sleep.csv 2>/dev/null || echo 0)
if [ "$SLEEP_SIZE" -lt 100 ]; then
    echo "ERROR: Sleep.csv download failed (size: ${SLEEP_SIZE} bytes)"
    exit 1
fi
echo "Sleep.csv downloaded: ${SLEEP_SIZE} bytes"

# 2. Invisibility Cloak dataset (Field, 2013) — field experiment on mischievous behavior
#    Variables: Mischief (count), Cloak (0=no cloak, 1=cloak)
wget -q -O "/opt/jamovi_datasets/Invisibility Cloak.csv" \
    "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/2.%20T-Tests/Invisibility%20Cloak.csv"

CLOAK_SIZE=$(stat -c%s "/opt/jamovi_datasets/Invisibility Cloak.csv" 2>/dev/null || echo 0)
if [ "$CLOAK_SIZE" -lt 100 ]; then
    echo "ERROR: Invisibility Cloak.csv download failed (size: ${CLOAK_SIZE} bytes)"
    exit 1
fi
echo "Invisibility Cloak.csv downloaded: ${CLOAK_SIZE} bytes"

# 3. Viagra dataset (Field, 2013) — pharmacological study on dose and libido
#    Variables: dose (1=placebo, 2=low dose, 3=high dose), libido (1-9 rating), partnerLibido
wget -q -O "/opt/jamovi_datasets/Viagra.csv" \
    "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/3.%20ANOVA/Viagra.csv"

VIAGRA_SIZE=$(stat -c%s /opt/jamovi_datasets/Viagra.csv 2>/dev/null || echo 0)
if [ "$VIAGRA_SIZE" -lt 100 ]; then
    echo "ERROR: Viagra.csv download failed (size: ${VIAGRA_SIZE} bytes)"
    exit 1
fi
echo "Viagra.csv downloaded: ${VIAGRA_SIZE} bytes"

# 4. Exam Anxiety dataset (Field, 2013) — exam performance and anxiety study
#    Variables: Exam (%), Revise (hours), Anxiety (scale score), Gender
wget -q -O "/opt/jamovi_datasets/Exam Anxiety.csv" \
    "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/4.%20Regression/Exam%20Anxiety.csv"

EXAM_SIZE=$(stat -c%s "/opt/jamovi_datasets/Exam Anxiety.csv" 2>/dev/null || echo 0)
if [ "$EXAM_SIZE" -lt 100 ]; then
    echo "ERROR: Exam Anxiety.csv download failed (size: ${EXAM_SIZE} bytes)"
    exit 1
fi
echo "Exam Anxiety.csv downloaded: ${EXAM_SIZE} bytes"

# 5. Big Five Inventory Neuroticism items (Revelle, 2010, psych R package — bfi dataset)
#    Real item-level data: 2,800 participants rated N1-N5 on a 1-6 Likert scale.
#    Source: https://github.com/vincentarelbundock/Rdatasets/tree/master/csv/psych
#    We download the full bfi.csv and extract N1-N5 columns (indices 16-20), dropping NAs.
cat > /opt/jamovi_datasets/extract_bfi_neuroticism.py << 'PYEOF'
#!/usr/bin/env python3
"""Extract N1-N5 Neuroticism items from the bfi dataset (Revelle 2010, psych R package).

The bfi dataset has 2800 participants who rated 25 Big Five personality items on a 1-6 scale
(1 = Very Inaccurate, 6 = Very Accurate). N1-N5 are the five Neuroticism items.
Source: https://github.com/vincentarelbundock/Rdatasets/tree/master/csv/psych
"""
import urllib.request
import os

url = "https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/psych/bfi.csv"
bfi_path = "/opt/jamovi_datasets/bfi.csv"
output = "/home/ga/Documents/Jamovi/NeuroticiIndex.csv"

print(f"Downloading bfi.csv from Rdatasets GitHub...")
urllib.request.urlretrieve(url, bfi_path)

with open(bfi_path) as f:
    lines = f.readlines()

# N1-N5 are columns 16-20 in bfi.csv (0-indexed)
# Header: rownames,A1,...,A5,C1,...,C5,E1,...,E5,N1,N2,N3,N4,N5,O1,...,O5,gender,education,age
n_indices = [16, 17, 18, 19, 20]

complete_rows = []
for line in lines[1:]:
    parts = line.strip().split(',')
    vals = [parts[i] if i < len(parts) else '' for i in n_indices]
    if any(v in ('', 'NA') for v in vals):
        continue
    try:
        int_vals = [int(v) for v in vals]
        if all(1 <= v <= 6 for v in int_vals):
            complete_rows.append(int_vals)
    except ValueError:
        continue

os.makedirs(os.path.dirname(output), exist_ok=True)
out_lines = ['N1,N2,N3,N4,N5']
out_lines.extend(','.join(str(v) for v in row) for row in complete_rows)
with open(output, 'w') as f:
    f.write('\n'.join(out_lines) + '\n')
print(f"Extracted {len(complete_rows)} complete rows to {output}")
PYEOF
chmod +x /opt/jamovi_datasets/extract_bfi_neuroticism.py
echo "Created extract_bfi_neuroticism.py script"

# 6. ToothGrowth dataset (R built-in, Crampton 1947) — vitamin C and tooth growth in guinea pigs
#    Variables: len (tooth length), supp (OJ/VC supplement type), dose (0.5/1/2 mg/day)
#    Source: https://github.com/vincentarelbundock/Rdatasets
wget -q -O "/opt/jamovi_datasets/ToothGrowth.csv" \
    "https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/datasets/ToothGrowth.csv"
TG_SIZE=$(stat -c%s /opt/jamovi_datasets/ToothGrowth.csv 2>/dev/null || echo 0)
if [ "$TG_SIZE" -lt 100 ]; then
    echo "ERROR: ToothGrowth.csv download failed (size: ${TG_SIZE} bytes)"
    exit 1
fi
echo "ToothGrowth.csv downloaded: ${TG_SIZE} bytes"

# 7. TitanicSurvival dataset (carData R package) — individual-level Titanic passenger data
#    Variables: survived (yes/no), sex (female/male), age, passengerClass (1st/2nd/3rd)
#    Source: https://github.com/vincentarelbundock/Rdatasets
wget -q -O "/opt/jamovi_datasets/TitanicSurvival.csv" \
    "https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/carData/TitanicSurvival.csv"
TS_SIZE=$(stat -c%s /opt/jamovi_datasets/TitanicSurvival.csv 2>/dev/null || echo 0)
if [ "$TS_SIZE" -lt 100 ]; then
    echo "ERROR: TitanicSurvival.csv download failed (size: ${TS_SIZE} bytes)"
    exit 1
fi
echo "TitanicSurvival.csv downloaded: ${TS_SIZE} bytes"

# 8. InsectSprays dataset (R built-in, Beall 1942) — insect counts by spray type
#    Variables: count (insect count), spray (A-F factor)
#    Source: https://github.com/vincentarelbundock/Rdatasets
wget -q -O "/opt/jamovi_datasets/InsectSprays.csv" \
    "https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/datasets/InsectSprays.csv"
IS_SIZE=$(stat -c%s /opt/jamovi_datasets/InsectSprays.csv 2>/dev/null || echo 0)
if [ "$IS_SIZE" -lt 100 ]; then
    echo "ERROR: InsectSprays.csv download failed (size: ${IS_SIZE} bytes)"
    exit 1
fi
echo "InsectSprays.csv downloaded: ${IS_SIZE} bytes"

# 9. Extract full BFI-25 items (all 25 personality items + gender + age) from bfi.csv
cat > /opt/jamovi_datasets/extract_bfi25.py << 'PYEOF'
#!/usr/bin/env python3
"""Extract all 25 Big Five Inventory items + demographics from bfi.csv (Revelle 2010).

The bfi dataset has 2800 participants who rated 25 personality items on a 1-6 scale.
Items: A1-A5 (Agreeableness), C1-C5 (Conscientiousness), E1-E5 (Extraversion),
       N1-N5 (Neuroticism), O1-O5 (Openness).
Demographics: gender (1=Male, 2=Female), age.
"""
import os

bfi_path = "/opt/jamovi_datasets/bfi.csv"
output = "/home/ga/Documents/Jamovi/BFI25.csv"

with open(bfi_path) as f:
    lines = f.readlines()

# Header: rownames,A1,A2,A3,A4,A5,C1,C2,C3,C4,C5,E1,E2,E3,E4,E5,N1,N2,N3,N4,N5,O1,O2,O3,O4,O5,gender,education,age
# We want columns 1-25 (A1-O5), 26 (gender), 28 (age) — skip rownames(0) and education(27)
item_indices = list(range(1, 26))  # A1 through O5
gender_idx = 26
age_idx = 28

out_header = "A1,A2,A3,A4,A5,C1,C2,C3,C4,C5,E1,E2,E3,E4,E5,N1,N2,N3,N4,N5,O1,O2,O3,O4,O5,gender,age"
complete_rows = []

for line in lines[1:]:
    parts = line.strip().split(',')
    if len(parts) < 29:
        continue
    items = [parts[i] for i in item_indices]
    gender = parts[gender_idx]
    age = parts[age_idx]
    # Skip rows with any NA in items or demographics
    if any(v in ('', 'NA') for v in items + [gender, age]):
        continue
    try:
        int_items = [int(v) for v in items]
        int_gender = int(gender)
        int_age = int(age)
        if all(1 <= v <= 6 for v in int_items) and int_gender in (1, 2) and 10 <= int_age <= 100:
            row_str = ','.join(str(v) for v in int_items) + f',{int_gender},{int_age}'
            complete_rows.append(row_str)
    except ValueError:
        continue

os.makedirs(os.path.dirname(output), exist_ok=True)
with open(output, 'w') as f:
    f.write(out_header + '\n')
    f.write('\n'.join(complete_rows) + '\n')
print(f"Extracted {len(complete_rows)} complete rows to {output}")
PYEOF
chmod +x /opt/jamovi_datasets/extract_bfi25.py
echo "Created extract_bfi25.py script"

chmod -R 755 /opt/jamovi_datasets
echo "All datasets downloaded and verified."

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Jamovi installation complete ==="
