#!/bin/bash
set -e
echo "=== Setting up 16s_rrna_local_blast_profiling task ==="

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/UGENE_Data/blast/results
chown -R ga:ga /home/ga/UGENE_Data

# Clean up any existing files from previous runs
rm -f /home/ga/UGENE_Data/blast/ecoli_genome.*
rm -f /home/ga/UGENE_Data/blast/16s_query.*
rm -f /home/ga/UGENE_Data/blast/results/*

# Download E. coli K-12 genome (NC_000913.3)
echo "Downloading real E. coli genome..."
wget -q --timeout=30 -O /home/ga/UGENE_Data/blast/ecoli_genome.fasta "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NC_000913.3&rettype=fasta&retmode=text" || true

# Fallback source if E-utilities is rate-limited
if [ ! -s /home/ga/UGENE_Data/blast/ecoli_genome.fasta ]; then
    echo "Fallback: Downloading from FTP..."
    curl -sL "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz" | gunzip > /home/ga/UGENE_Data/blast/ecoli_genome.fasta
fi

# Download 16S query sequence
echo "Downloading 16S query sequence..."
wget -q --timeout=30 -O /home/ga/UGENE_Data/blast/16s_query.fasta "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NR_102804.1&rettype=fasta&retmode=text" || true

# Fallback strategy: Extract the first 16S from the downloaded genome (approx 225k-227k)
if [ ! -s /home/ga/UGENE_Data/blast/16s_query.fasta ]; then
    echo "Fallback: Generating 16S query from genome..."
    python3 -c "
import sys
try:
    with open('/home/ga/UGENE_Data/blast/ecoli_genome.fasta', 'r') as f:
        seq = ''.join(line.strip() for line in f if not line.startswith('>'))
        if len(seq) > 230000:
            with open('/home/ga/UGENE_Data/blast/16s_query.fasta', 'w') as out:
                out.write('>16s_query_fallback\n' + seq[225000:226500] + '\n')
except Exception as e:
    print('Failed to generate fallback query:', e)
    "
fi

# Apply correct ownership
chown -R ga:ga /home/ga/UGENE_Data/blast

# Launch UGENE
echo "Starting UGENE..."
pkill -f "ugene" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh > /dev/null 2>&1 &"

# Wait for application window to open
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected."
        break
    fi
    sleep 1
done

# Maximize and focus the UI
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
    # Dismiss any first-run tip dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="