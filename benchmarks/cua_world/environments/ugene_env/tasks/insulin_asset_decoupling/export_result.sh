#!/bin/bash
echo "=== Exporting insulin_asset_decoupling results ==="

# Record task boundaries
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DIR="/home/ga/UGENE_Data/pipeline_assets"

# Initialize state variables
DIR_EXISTS="false"
REF_EXISTS="false"
REF_LEN=0
GFF_EXISTS="false"
CDS_COUNT=0
GENE_COUNT=0
PROT_EXISTS="false"
PROT_LEN=0
PROT_SEQ=""
MANIFEST_EXISTS="false"
MANIFEST_B64=""

# Check Directory
if [ -d "$DIR" ]; then
    DIR_EXISTS="true"
fi

# Check Reference FASTA
if [ -f "$DIR/insulin_reference.fasta" ]; then
    REF_EXISTS="true"
    # Filter out header lines and count sequence characters
    REF_LEN=$(grep -v "^>" "$DIR/insulin_reference.fasta" | tr -d '\n\r\t ' | wc -c)
fi

# Check Annotation GFF/GFF3
if [ -f "$DIR/insulin_annotations.gff" ] || [ -f "$DIR/insulin_annotations.gff3" ]; then
    GFF_EXISTS="true"
    GFF_FILE="$DIR/insulin_annotations.gff"
    [ -f "$DIR/insulin_annotations.gff3" ] && GFF_FILE="$DIR/insulin_annotations.gff3"
    
    # In valid GFF, the 3rd column is the feature type
    CDS_COUNT=$(awk -F'\t' '$3 == "CDS" {print}' "$GFF_FILE" 2>/dev/null | wc -l)
    GENE_COUNT=$(awk -F'\t' '$3 == "gene" {print}' "$GFF_FILE" 2>/dev/null | wc -l)
fi

# Check Protein FASTA
if [ -f "$DIR/insulin_protein.fasta" ]; then
    PROT_EXISTS="true"
    PROT_LEN=$(grep -v "^>" "$DIR/insulin_protein.fasta" | tr -d '\n\r\t ' | wc -c)
    # Extract first 200 characters of the sequence to check for amino acid alphabet
    PROT_SEQ=$(grep -v "^>" "$DIR/insulin_protein.fasta" | tr -d '\n\r\t ' | head -c 200)
fi

# Check Manifest File
if [ -f "$DIR/manifest.txt" ]; then
    MANIFEST_EXISTS="true"
    # Base64 encode the manifest to safely transport it within JSON
    MANIFEST_B64=$(cat "$DIR/manifest.txt" | tr -d '\r' | base64 -w 0)
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Construct JSON payload securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dir_exists": $DIR_EXISTS,
    "ref_exists": $REF_EXISTS,
    "ref_len": $REF_LEN,
    "gff_exists": $GFF_EXISTS,
    "cds_count": $CDS_COUNT,
    "gene_count": $GENE_COUNT,
    "prot_exists": $PROT_EXISTS,
    "prot_len": $PROT_LEN,
    "prot_seq": "$PROT_SEQ",
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_b64": "$MANIFEST_B64"
}
EOF

# Ensure safe transfer to accessible temp directory
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved successfully."
echo "=== Export complete ==="