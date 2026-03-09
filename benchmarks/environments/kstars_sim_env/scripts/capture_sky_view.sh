#!/bin/bash
# Capture the sky view based on current telescope pointing.
#
# Workflow:
# 1. Read current telescope RA/Dec from INDI
# 2. Convert RA from hours to degrees
# 3. Fetch real sky survey image from CDS hips2fits service
#    (renders DSS2 Color imagery dynamically for the given coordinates)
# 4. Apply false color enhancement
#
# The captured image shows what the telescope is actually pointing at,
# rendered from real sky survey data. Different telescope positions
# produce different images — the content is entirely determined by
# where the telescope is pointed.
#
# Usage: bash capture_sky_view.sh [output_path] [fov_degrees] [--palette PALETTE]
#   output_path: where to save the capture (default: ~/Images/captures/sky_capture_<timestamp>.png)
#   fov_degrees: field of view in degrees (default: 1.0)
#   --palette: false color palette (default: enhanced)
#
# Available palettes: enhanced, hubble, narrowband, heat, cool, vibrant

set -e

# Parse arguments: capture_sky_view.sh [output] [fov] [--palette NAME]
OUTPUT=""
FOV=""
PALETTE="enhanced"

while [ $# -gt 0 ]; do
    case "$1" in
        --palette)
            PALETTE="$2"; shift 2 ;;
        --palette=*)
            PALETTE="${1#*=}"; shift ;;
        *)
            if [ -z "$OUTPUT" ]; then
                OUTPUT="$1"
            elif [ -z "$FOV" ]; then
                FOV="$1"
            fi
            shift ;;
    esac
done

OUTPUT="${OUTPUT:-/home/ga/Images/captures/sky_capture_$(date +%Y%m%d_%H%M%S).png}"
FOV="${FOV:-1.0}"

WIDTH=1920
HEIGHT=1080
HIPS_SURVEY="CDS%2FP%2FDSS2%2Fcolor"
HIPS_URL="https://alasky.cds.unistra.fr/hips-image-services/hips2fits"

mkdir -p "$(dirname "$OUTPUT")"

echo "=== Capturing Sky View ==="

# ── 1. Get current telescope position from INDI ──────────────────────
RA_HOURS=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null)
DEC_DEG=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null)

if [ -z "$RA_HOURS" ] || [ -z "$DEC_DEG" ]; then
    echo "ERROR: Cannot read telescope position from INDI"
    echo "  Make sure the telescope simulator is connected."
    exit 1
fi

echo "  Telescope pointing: RA=${RA_HOURS}h, Dec=${DEC_DEG}°"

# ── 2. Convert RA from hours to degrees (RA_deg = RA_hours × 15) ────
RA_DEG=$(python3 -c "print(float('${RA_HOURS}') * 15.0)")

echo "  Coordinates: RA=${RA_DEG}°, Dec=${DEC_DEG}° (FOV=${FOV}°)"

# ── 3. Fetch sky image from CDS hips2fits ─────────────────────────────
# hips2fits renders HiPS sky survey tiles on the server side.
# DSS2 Color provides digitized photographic survey data from
# Palomar, AAO, and ESO Schmidt telescopes — the definitive
# optical all-sky survey used by professional astronomers.
echo "  Fetching DSS2 Color sky survey image..."

FETCH_URL="${HIPS_URL}?hips=${HIPS_SURVEY}&width=${WIDTH}&height=${HEIGHT}&fov=${FOV}&ra=${RA_DEG}&dec=${DEC_DEG}&projection=TAN&format=png"

RAW_OUTPUT="${OUTPUT%.png}_raw.png"

if curl -sf -o "$RAW_OUTPUT" "$FETCH_URL"; then
    FILE_SIZE=$(stat -c%s "$RAW_OUTPUT" 2>/dev/null || stat -f%z "$RAW_OUTPUT" 2>/dev/null)
    echo "  Raw capture: $RAW_OUTPUT ($(numfmt --to=iec $FILE_SIZE 2>/dev/null || echo "${FILE_SIZE}B"))"
else
    echo "ERROR: Failed to fetch sky image from CDS hips2fits"
    echo "  URL: $FETCH_URL"
    echo "  Check network connectivity."
    exit 1
fi

# ── 4. Apply false color enhancement ──────────────────────────────────
echo "  Applying false color (palette: ${PALETTE})..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FC_SCRIPT="${SCRIPT_DIR}/false_color.py"
if [ ! -f "$FC_SCRIPT" ]; then
    FC_SCRIPT="/workspace/scripts/false_color.py"
fi
if [ ! -f "$FC_SCRIPT" ]; then
    FC_SCRIPT="/home/ga/false_color.py"
fi

if python3 "$FC_SCRIPT" "$RAW_OUTPUT" "$OUTPUT" --palette "$PALETTE" 2>/dev/null; then
    echo "  Enhanced: $OUTPUT"
else
    echo "  Enhancement skipped, using raw capture"
    cp "$RAW_OUTPUT" "$OUTPUT"
fi

echo ""
echo "=== Capture Complete ==="
echo "  Raw:      $RAW_OUTPUT"
echo "  Enhanced: $OUTPUT"
echo "  Telescope: RA=${RA_HOURS}h (${RA_DEG}°), Dec=${DEC_DEG}°"
echo "  FOV: ${FOV}°, Palette: ${PALETTE}"
echo "  Survey: DSS2 Color (Digitized Sky Survey)"
