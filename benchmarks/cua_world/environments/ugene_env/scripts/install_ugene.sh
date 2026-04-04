#!/bin/bash
set -e

echo "=== Installing UGENE Bioinformatics Suite ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install system dependencies
# UGENE needs Qt5 runtime, OpenGL, and various system libraries
apt-get install -y \
    libqt5core5a libqt5gui5 libqt5widgets5 libqt5xml5 libqt5network5 \
    libqt5svg5 libqt5printsupport5 libqt5opengl5 libqt5script5 \
    libgl1-mesa-glx libglu1-mesa libegl1 \
    libxcb-xinerama0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
    libxcb-render-util0 libxcb-shape0 libxkbcommon-x11-0 \
    libxcb-cursor0 \
    wget curl ca-certificates \
    scrot wmctrl xdotool x11-utils xclip \
    python3-pip python3-numpy \
    unzip tar gzip \
    default-jre

echo "=== Downloading UGENE 53.0 ==="

# Download UGENE tar.gz from GitHub releases
UGENE_URL="https://github.com/ugeneunipro/ugene/releases/download/53.0/ugene-53.0-linux-x86-64.tar.gz"
UGENE_FALLBACK="https://github.com/ugeneunipro/ugene/releases/download/51.0/ugene-51.0-linux-x86-64.tar.gz"

mkdir -p /opt/ugene
cd /tmp

# Try primary URL, then fallback
if wget --timeout=300 -q "$UGENE_URL" -O ugene.tar.gz && [ -s ugene.tar.gz ]; then
    echo "Downloaded UGENE 53.0"
elif wget --timeout=300 -q "$UGENE_FALLBACK" -O ugene.tar.gz && [ -s ugene.tar.gz ]; then
    echo "Downloaded UGENE 51.0 (fallback)"
else
    echo "ERROR: Could not download UGENE"
    exit 1
fi

# Extract UGENE
tar -xzf ugene.tar.gz -C /opt/ugene --strip-components=1
rm -f ugene.tar.gz

# Verify installation
if [ ! -f /opt/ugene/ugene ] && [ ! -f /opt/ugene/ugeneui ]; then
    # Try to find the actual binary
    UGENE_BIN=$(find /opt/ugene -name "ugene" -type f -executable 2>/dev/null | head -1)
    if [ -z "$UGENE_BIN" ]; then
        UGENE_BIN=$(find /opt/ugene -name "ugeneui" -type f -executable 2>/dev/null | head -1)
    fi
    if [ -z "$UGENE_BIN" ]; then
        echo "WARNING: Could not find UGENE binary, listing /opt/ugene:"
        ls -la /opt/ugene/
        find /opt/ugene -type f -executable | head -20
    fi
fi

# Create wrapper script in PATH
cat > /usr/local/bin/ugene << 'WRAPPER'
#!/bin/bash
export DISPLAY="${DISPLAY:-:1}"
export LD_LIBRARY_PATH="/opt/ugene:$LD_LIBRARY_PATH"
cd /opt/ugene
if [ -x ./ugeneui ]; then
    exec ./ugeneui "$@"
elif [ -x ./ugene ]; then
    exec ./ugene "$@"
else
    UGENE_BIN=$(find /opt/ugene -name "ugene*" -type f -executable | head -1)
    if [ -n "$UGENE_BIN" ]; then
        exec "$UGENE_BIN" "$@"
    else
        echo "ERROR: Cannot find UGENE executable"
        exit 1
    fi
fi
WRAPPER
chmod +x /usr/local/bin/ugene

# Set permissions
chmod -R 755 /opt/ugene
chown -R root:root /opt/ugene

echo "=== Downloading Real Bioinformatics Data ==="

# Create data directory
mkdir -p /opt/ugene_data

# --- Download real hemoglobin beta protein sequences from multiple species ---
# These are real protein sequences from NCBI/UniProt for hemoglobin beta subunit
# Used for multiple sequence alignment task
echo "Downloading hemoglobin beta protein sequences from UniProt..."

# Download individual sequences from UniProt REST API and combine
# Human HBB (P68871), Mouse Hbb-b1 (P02088), Chicken HBB (P02112),
# Frog HBB (P02132), Zebrafish HBB (Q90485), Bovine HBB (P02070),
# Horse HBB (P02062), Pig HBB (P02067)
ACCESSIONS="P68871,P02088,P02112,P02132,Q90485,P02070,P02062,P02067"
wget --timeout=120 -q \
    "https://rest.uniprot.org/uniprotkb/stream?query=accession:${ACCESSIONS}&format=fasta" \
    -O /opt/ugene_data/hemoglobin_beta_multispecies.fasta || true

# Verify download succeeded and has content
if [ ! -s /opt/ugene_data/hemoglobin_beta_multispecies.fasta ]; then
    echo "UniProt batch download failed, trying individual downloads..."
    > /opt/ugene_data/hemoglobin_beta_multispecies.fasta
    for acc in P68871 P02088 P02112 P02132 Q90485 P02070 P02062 P02067; do
        wget --timeout=60 -q \
            "https://rest.uniprot.org/uniprotkb/${acc}.fasta" \
            -O /tmp/seq_${acc}.fasta 2>/dev/null || true
        if [ -s /tmp/seq_${acc}.fasta ]; then
            cat /tmp/seq_${acc}.fasta >> /opt/ugene_data/hemoglobin_beta_multispecies.fasta
        fi
        rm -f /tmp/seq_${acc}.fasta
    done
fi

# Verify we have sequences; fall back to bundled assets if download failed
SEQ_COUNT=$(grep -c "^>" /opt/ugene_data/hemoglobin_beta_multispecies.fasta 2>/dev/null || echo "0")
if [ "$SEQ_COUNT" -lt 8 ] && [ -s /workspace/assets/hemoglobin_beta_multispecies.fasta ]; then
    echo "Using bundled hemoglobin data from assets (download incomplete: ${SEQ_COUNT}/8)"
    cp /workspace/assets/hemoglobin_beta_multispecies.fasta /opt/ugene_data/hemoglobin_beta_multispecies.fasta
    SEQ_COUNT=$(grep -c "^>" /opt/ugene_data/hemoglobin_beta_multispecies.fasta 2>/dev/null || echo "0")
fi
echo "Downloaded ${SEQ_COUNT} hemoglobin beta sequences"

# --- Download real GenBank record: Human insulin gene ---
echo "Downloading human insulin gene GenBank record from NCBI..."
# Try multiple accession numbers for insulin gene
wget --timeout=120 -q \
    "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NM_000207.3&rettype=gb&retmode=text" \
    -O /opt/ugene_data/human_insulin_gene.gb || true

if [ ! -s /opt/ugene_data/human_insulin_gene.gb ]; then
    echo "Trying alternative accession..."
    wget --timeout=120 -q \
        "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=J00265.1&rettype=gb&retmode=text" \
        -O /opt/ugene_data/human_insulin_gene.gb || true
fi

if [ ! -s /opt/ugene_data/human_insulin_gene.gb ]; then
    echo "WARNING: Could not download insulin GenBank record (non-critical)"
fi

# --- Download a real PDB structure: Hemoglobin (4HHB) ---
echo "Downloading hemoglobin crystal structure (PDB 4HHB) from RCSB..."
wget --timeout=120 -q \
    "https://files.rcsb.org/download/4HHB.pdb" \
    -O /opt/ugene_data/hemoglobin_4HHB.pdb || true

if [ ! -s /opt/ugene_data/hemoglobin_4HHB.pdb ]; then
    echo "WARNING: Could not download PDB structure"
fi

# --- Download cytochrome c sequences for phylogenetic tree task ---
echo "Downloading cytochrome c protein sequences from UniProt..."
# Cytochrome c from diverse species: ideal for phylogenetic tree building
# Human (P99999), Chicken (P67881), Neurospora crassa (P00048), Cannabis sativa (P00053),
# Yeast (P00044), Drosophila (P04657), Horse (P00004), Pig (P62895)
CYT_ACCESSIONS="P99999,P67881,P00048,P00053,P00044,P04657,P00004,P62895"
wget --timeout=120 -q \
    "https://rest.uniprot.org/uniprotkb/stream?query=accession:${CYT_ACCESSIONS}&format=fasta" \
    -O /opt/ugene_data/cytochrome_c_multispecies.fasta || true

if [ ! -s /opt/ugene_data/cytochrome_c_multispecies.fasta ]; then
    echo "UniProt batch download failed for cytochrome c, trying individual..."
    > /opt/ugene_data/cytochrome_c_multispecies.fasta
    for acc in P99999 P67881 P00048 P00053 P00044 P04657 P00004 P62895; do
        wget --timeout=60 -q \
            "https://rest.uniprot.org/uniprotkb/${acc}.fasta" \
            -O /tmp/seq_${acc}.fasta 2>/dev/null || true
        if [ -s /tmp/seq_${acc}.fasta ]; then
            cat /tmp/seq_${acc}.fasta >> /opt/ugene_data/cytochrome_c_multispecies.fasta
        fi
        rm -f /tmp/seq_${acc}.fasta
    done
fi

# Verify we have sequences; fall back to bundled assets if download failed
CYT_COUNT=$(grep -c "^>" /opt/ugene_data/cytochrome_c_multispecies.fasta 2>/dev/null || echo "0")
if [ "$CYT_COUNT" -lt 8 ] && [ -s /workspace/assets/cytochrome_c_multispecies.fasta ]; then
    echo "Using bundled cytochrome c data from assets (download incomplete: ${CYT_COUNT}/8)"
    cp /workspace/assets/cytochrome_c_multispecies.fasta /opt/ugene_data/cytochrome_c_multispecies.fasta
    CYT_COUNT=$(grep -c "^>" /opt/ugene_data/cytochrome_c_multispecies.fasta 2>/dev/null || echo "0")
fi
echo "Downloaded ${CYT_COUNT} cytochrome c sequences"

# Set data permissions
chmod -R 755 /opt/ugene_data
chown -R root:root /opt/ugene_data

echo "=== UGENE installation complete ==="
echo "UGENE location: /opt/ugene"
echo "Data location: /opt/ugene_data"
ls -la /opt/ugene_data/
