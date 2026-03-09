#!/bin/bash
set -e

echo "=== Installing PyMOL Molecular Visualization System ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install PyMOL and dependencies
apt-get install -y \
    pymol \
    python3-pymol \
    python3-pyqt5 \
    python3-pyqt5.qtopengl \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    mesa-utils \
    python3-pip \
    python3-numpy \
    python3-scipy \
    wget \
    curl \
    xdotool \
    wmctrl \
    scrot \
    x11-utils \
    xauth

# Install biopython for working with PDB files
pip3 install biopython 2>/dev/null || pip3 install --break-system-packages biopython 2>/dev/null || true

# Create data directories
mkdir -p /opt/pymol_data/structures
mkdir -p /opt/pymol_data/sessions

# Download real PDB structures from RCSB Protein Data Bank
echo "=== Downloading real PDB structures from RCSB ==="

# 4HHB - Human Hemoglobin (classic multi-chain protein, 4 chains A/B/C/D)
wget -q "https://files.rcsb.org/download/4HHB.pdb" -O /opt/pymol_data/structures/4HHB.pdb || \
    curl -sL "https://files.rcsb.org/download/4HHB.pdb" -o /opt/pymol_data/structures/4HHB.pdb || true

# 1UBQ - Ubiquitin (small, well-studied protein, 76 residues)
wget -q "https://files.rcsb.org/download/1UBQ.pdb" -O /opt/pymol_data/structures/1UBQ.pdb || \
    curl -sL "https://files.rcsb.org/download/1UBQ.pdb" -o /opt/pymol_data/structures/1UBQ.pdb || true

# 1CRN - Crambin (very small protein, 46 residues, great for quick rendering)
wget -q "https://files.rcsb.org/download/1CRN.pdb" -O /opt/pymol_data/structures/1CRN.pdb || \
    curl -sL "https://files.rcsb.org/download/1CRN.pdb" -o /opt/pymol_data/structures/1CRN.pdb || true

# Verify downloads
echo "=== Verifying downloaded PDB files ==="
for pdb in 4HHB 1UBQ 1CRN; do
    if [ -f "/opt/pymol_data/structures/${pdb}.pdb" ] && [ -s "/opt/pymol_data/structures/${pdb}.pdb" ]; then
        SIZE=$(stat -c%s "/opt/pymol_data/structures/${pdb}.pdb")
        echo "  ${pdb}.pdb: ${SIZE} bytes - OK"
    else
        echo "  WARNING: ${pdb}.pdb missing or empty"
    fi
done

# Set permissions
chmod -R 755 /opt/pymol_data
chown -R root:root /opt/pymol_data

# Verify PyMOL installation
echo "=== Verifying PyMOL installation ==="
pymol --version 2>/dev/null || pymol -qc -d "print('PyMOL installed successfully'); quit" 2>/dev/null || echo "PyMOL binary available at: $(which pymol)"

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== PyMOL installation complete ==="
