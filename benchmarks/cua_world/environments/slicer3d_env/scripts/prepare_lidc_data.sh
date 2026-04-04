#!/bin/bash
# Prepare LIDC-IDRI data for lung nodule detection task
# Downloads a single chest CT case from The Cancer Imaging Archive (TCIA)

set -e

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
DOWNLOAD_DIR="/tmp/lidc_download"
PATIENT_ID="${1:-LIDC-IDRI-0001}"

echo "=== Preparing LIDC-IDRI Data ==="
echo "Data directory: $LIDC_DIR"
echo "Patient ID: $PATIENT_ID"

mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$DOWNLOAD_DIR"

# Check if data already exists
if [ -d "$LIDC_DIR/$PATIENT_ID/DICOM" ] && [ "$(ls -1 "$LIDC_DIR/$PATIENT_ID/DICOM/" 2>/dev/null | wc -l)" -gt 50 ]; then
    echo "LIDC data already exists for $PATIENT_ID"
    # Check if ground truth exists too
    if [ -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_nodules.json" ]; then
        echo "Ground truth already exists"
        exit 0
    fi
fi

# ============================================================
# Step 1: Download CT DICOM series via TCIA REST API
# ============================================================
echo "Downloading LIDC-IDRI CT series for $PATIENT_ID..."

TCIA_BASE="https://services.cancerimagingarchive.net/nbia-api/services/v1"

# Get list of series for this patient
echo "Querying available series..."
SERIES_JSON=$(curl -s "$TCIA_BASE/getSeries?Collection=LIDC-IDRI&PatientID=$PATIENT_ID" 2>/dev/null || echo "[]")

if [ "$SERIES_JSON" = "[]" ] || [ -z "$SERIES_JSON" ]; then
    echo "WARNING: Could not query TCIA API for $PATIENT_ID"
    echo "Trying alternative API endpoint..."
    SERIES_JSON=$(curl -s "https://services.cancerimagingarchive.net/services/v4/getSeriesList?Collection=LIDC-IDRI&PatientID=$PATIENT_ID" 2>/dev/null || echo "[]")
fi

# Extract the first CT series UID
SERIES_UID=$(echo "$SERIES_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Find CT series (largest series, likely the main CT scan)
    ct_series = [s for s in data if s.get('Modality', '') == 'CT']
    if ct_series:
        # Sort by image count descending, pick the one with most images
        ct_series.sort(key=lambda x: int(x.get('ImageCount', 0)), reverse=True)
        print(ct_series[0]['SeriesInstanceUID'])
    elif data:
        print(data[0]['SeriesInstanceUID'])
except Exception as e:
    print('', file=sys.stderr)
" 2>/dev/null || echo "")

if [ -z "$SERIES_UID" ]; then
    echo "ERROR: Could not find CT series for $PATIENT_ID"
    echo "API response: $SERIES_JSON"
    exit 1
fi

echo "Found CT series: $SERIES_UID"

# Download the DICOM images
DICOM_ZIP="$DOWNLOAD_DIR/${PATIENT_ID}_dicom.zip"
if [ ! -f "$DICOM_ZIP" ] || [ "$(stat -c%s "$DICOM_ZIP" 2>/dev/null || echo 0)" -lt 1000000 ]; then
    echo "Downloading DICOM series..."
    curl -L -o "$DICOM_ZIP" \
        "$TCIA_BASE/getImage?SeriesInstanceUID=$SERIES_UID" 2>/dev/null

    if [ ! -f "$DICOM_ZIP" ] || [ "$(stat -c%s "$DICOM_ZIP" 2>/dev/null || echo 0)" -lt 1000000 ]; then
        echo "ERROR: Failed to download DICOM series"
        exit 1
    fi
    echo "Download complete: $(du -h "$DICOM_ZIP" | cut -f1)"
fi

# Extract DICOM files
echo "Extracting DICOM files..."
mkdir -p "$LIDC_DIR/$PATIENT_ID/DICOM"
unzip -o -q "$DICOM_ZIP" -d "$LIDC_DIR/$PATIENT_ID/DICOM/"

DICOM_COUNT=$(find "$LIDC_DIR/$PATIENT_ID/DICOM" -name "*.dcm" -o -name "*.DCM" -o -type f ! -name ".*" | wc -l)
echo "Extracted $DICOM_COUNT DICOM files"

if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Too few DICOM files extracted ($DICOM_COUNT)"
    exit 1
fi

# ============================================================
# Step 2: Download and parse LIDC-IDRI XML annotations
# ============================================================
echo "Downloading LIDC-IDRI annotations..."

ANNOT_ZIP="$DOWNLOAD_DIR/lidc_xml_annotations.zip"
if [ ! -f "$ANNOT_ZIP" ] || [ "$(stat -c%s "$ANNOT_ZIP" 2>/dev/null || echo 0)" -lt 10000 ]; then
    # Try to download annotation XML for this patient
    # LIDC annotations are often bundled separately
    curl -L -o "$ANNOT_ZIP" \
        "https://www.cancerimagingarchive.net/wp-content/uploads/LIDC-XML-only.zip" 2>/dev/null || true
fi

# Extract annotations
ANNOT_DIR="$DOWNLOAD_DIR/annotations"
mkdir -p "$ANNOT_DIR"

if [ -f "$ANNOT_ZIP" ] && [ "$(stat -c%s "$ANNOT_ZIP" 2>/dev/null || echo 0)" -gt 10000 ]; then
    echo "Extracting annotation XML files..."
    unzip -o -q "$ANNOT_ZIP" -d "$ANNOT_DIR/" 2>/dev/null || true
fi

# Find the annotation XML for our patient
PATIENT_NUM=$(echo "$PATIENT_ID" | grep -oE '[0-9]+$' || echo "0001")
ANNOT_XML=$(find "$ANNOT_DIR" -name "*${PATIENT_NUM}*" -o -name "*${PATIENT_ID}*" 2>/dev/null | head -1)

# ============================================================
# Step 3: Parse annotations and create ground truth JSON
# ============================================================
echo "Creating ground truth nodule data..."

python3 << 'PYEOF'
import json
import os
import sys
import glob
import xml.etree.ElementTree as ET

patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")
annot_dir = os.environ.get("ANNOT_DIR", "/tmp/lidc_download/annotations")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
dicom_dir = os.environ.get("DICOM_DIR", f"/home/ga/Documents/SlicerData/LIDC/{patient_id}/DICOM")

# Try to find annotation XML
patient_num = patient_id.split("-")[-1] if "-" in patient_id else "0001"
xml_files = []
for pattern in [f"*{patient_num}*", f"*{patient_id}*"]:
    xml_files.extend(glob.glob(os.path.join(annot_dir, "**", pattern), recursive=True))

nodules = []

if xml_files:
    xml_path = xml_files[0]
    print(f"Found annotation XML: {xml_path}")

    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()

        # Handle LIDC namespace
        ns = {}
        if root.tag.startswith("{"):
            ns_uri = root.tag.split("}")[0] + "}"
            ns = {"lidc": ns_uri.strip("{}")}

        # Parse all reading sessions
        reading_sessions = (
            root.findall(".//readingSession") or
            root.findall(".//{*}readingSession") or
            root.findall(".//lidc:readingSession", ns) or
            []
        )

        print(f"Found {len(reading_sessions)} reading sessions")

        # Collect nodules from all readers
        all_nodules_by_reader = []
        for session in reading_sessions:
            reader_nodules = []
            unblinded = (
                session.findall("unblindedReadNodule") or
                session.findall("{*}unblindedReadNodule") or
                session.findall("lidc:unblindedReadNodule", ns) or
                []
            )

            for nodule in unblinded:
                rois = (
                    nodule.findall("roi") or
                    nodule.findall("{*}roi") or
                    nodule.findall("lidc:roi", ns) or
                    []
                )

                if not rois:
                    continue

                all_x, all_y, all_z = [], [], []
                for roi in rois:
                    z_elem = (
                        roi.find("imageZposition") or
                        roi.find("{*}imageZposition") or
                        roi.find("lidc:imageZposition", ns)
                    )
                    if z_elem is not None and z_elem.text:
                        z = float(z_elem.text)
                    else:
                        continue

                    edges = (
                        roi.findall("edgeMap") or
                        roi.findall("{*}edgeMap") or
                        roi.findall("lidc:edgeMap", ns) or
                        []
                    )
                    for edge in edges:
                        x_elem = edge.find("xCoord") or edge.find("{*}xCoord") or edge.find("lidc:xCoord", ns)
                        y_elem = edge.find("yCoord") or edge.find("{*}yCoord") or edge.find("lidc:yCoord", ns)
                        if x_elem is not None and y_elem is not None:
                            all_x.append(float(x_elem.text))
                            all_y.append(float(y_elem.text))
                            all_z.append(z)

                if all_x:
                    import numpy as np
                    centroid = (float(np.mean(all_x)), float(np.mean(all_y)), float(np.mean(all_z)))
                    diameter = max(max(all_x) - min(all_x), max(all_y) - min(all_y))
                    reader_nodules.append({
                        "centroid_xyz": list(centroid),
                        "diameter_pixels": float(diameter),
                    })

            all_nodules_by_reader.append(reader_nodules)

        # Consensus: A nodule is "real" if found by >= 2 of 4 readers
        # Match nodules across readers by proximity
        if all_nodules_by_reader:
            import numpy as np
            consensus_nodules = []

            # Use first reader as reference, match others
            for ref_nod in all_nodules_by_reader[0]:
                ref_c = np.array(ref_nod["centroid_xyz"])
                agreement = 1
                diameters = [ref_nod["diameter_pixels"]]

                for other_reader in all_nodules_by_reader[1:]:
                    for other_nod in other_reader:
                        other_c = np.array(other_nod["centroid_xyz"])
                        dist = np.linalg.norm(ref_c - other_c)
                        if dist < 30:  # Within 30 pixels
                            agreement += 1
                            diameters.append(other_nod["diameter_pixels"])
                            break

                if agreement >= 2:
                    consensus_nodules.append({
                        "centroid_xyz": ref_nod["centroid_xyz"],
                        "diameter_pixels": float(np.mean(diameters)),
                        "reader_agreement": agreement,
                    })

            nodules = consensus_nodules

    except Exception as e:
        print(f"Error parsing XML: {e}")

# If no XML annotations available, try to get DICOM spacing info
# to create placeholder ground truth with known data
try:
    import pydicom
    dcm_files = glob.glob(os.path.join(dicom_dir, "**", "*.dcm"), recursive=True)
    if not dcm_files:
        dcm_files = [f for f in glob.glob(os.path.join(dicom_dir, "**", "*"), recursive=True)
                      if os.path.isfile(f) and not f.startswith(".")]

    if dcm_files:
        ds = pydicom.dcmread(dcm_files[0])
        pixel_spacing = list(ds.PixelSpacing) if hasattr(ds, "PixelSpacing") else [1.0, 1.0]
        slice_thickness = float(ds.SliceThickness) if hasattr(ds, "SliceThickness") else 1.0

        # Convert pixel diameters to mm
        for nod in nodules:
            nod["diameter_mm"] = nod["diameter_pixels"] * float(pixel_spacing[0])
            nod["centroid_mm"] = [
                nod["centroid_xyz"][0] * float(pixel_spacing[0]),
                nod["centroid_xyz"][1] * float(pixel_spacing[1]),
                nod["centroid_xyz"][2],  # Z is already in mm (imageZposition)
            ]
    else:
        # Assume 1mm spacing if no DICOM found
        for nod in nodules:
            nod["diameter_mm"] = nod["diameter_pixels"]
            nod["centroid_mm"] = nod["centroid_xyz"]
except ImportError:
    # pydicom not available, assume 1mm pixel spacing
    for nod in nodules:
        nod["diameter_mm"] = nod.get("diameter_pixels", 0)
        nod["centroid_mm"] = nod.get("centroid_xyz", [0, 0, 0])

# Filter to nodules >= 3mm
significant_nodules = [n for n in nodules if n.get("diameter_mm", 0) >= 3.0]

# Assign approximate lobe locations based on Z position
# (simplified - would need actual anatomical mapping for real use)
for nod in significant_nodules:
    z = nod["centroid_mm"][2] if "centroid_mm" in nod else 0
    x = nod["centroid_mm"][0] if "centroid_mm" in nod else 0
    # Very rough: right lung is x < 256 (assuming 512 matrix), left is x >= 256
    side = "R" if x < 256 else "L"
    # Very rough z-based lobe assignment
    if z > 0:
        lobe = f"{side}UL"
    else:
        lobe = f"{side}LL"
    nod["approximate_lobe"] = lobe

# Save ground truth
gt_data = {
    "patient_id": patient_id,
    "total_nodules_found": len(significant_nodules),
    "nodules": significant_nodules,
    "nodule_count_all_sizes": len(nodules),
    "minimum_diameter_mm": 3.0,
}

gt_path = os.path.join(gt_dir, f"{patient_id}_nodules.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(f"  Total nodules (>= 3mm): {len(significant_nodules)}")
for i, n in enumerate(significant_nodules):
    print(f"  Nodule {i+1}: diameter={n.get('diameter_mm', '?'):.1f}mm, "
          f"location=({n['centroid_xyz'][0]:.0f},{n['centroid_xyz'][1]:.0f},{n['centroid_xyz'][2]:.0f}), "
          f"readers={n.get('reader_agreement', '?')}")
PYEOF

# Set permissions
chown -R ga:ga "$LIDC_DIR" 2>/dev/null || true
chmod -R 755 "$LIDC_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Save patient ID for other scripts
echo "$PATIENT_ID" > /tmp/lidc_patient_id

# Cleanup
rm -f "$DICOM_ZIP" 2>/dev/null || true

echo ""
echo "=== LIDC Data Preparation Complete ==="
echo "Patient ID: $PATIENT_ID"
echo "DICOM location: $LIDC_DIR/$PATIENT_ID/DICOM/"
echo "DICOM files: $(find "$LIDC_DIR/$PATIENT_ID/DICOM" -type f | wc -l)"
