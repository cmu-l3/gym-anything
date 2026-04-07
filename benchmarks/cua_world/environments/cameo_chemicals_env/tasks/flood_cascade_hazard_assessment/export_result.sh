#!/bin/bash
# export_result.sh - Post-task hook for flood_cascade_hazard_assessment
# Exports agent's flood corridor assessment content for verification

echo "=== Exporting flood_cascade_hazard_assessment result ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true
echo "Final screenshot saved"

# Compute elapsed time
START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# Check output file
OUTPUT_FILE="/home/ga/Documents/flood_cascade_assessment.txt"
INITIAL_EXISTS=$(cat /tmp/initial_output_file_exists 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=1
    FILE_SIZE=$(wc -c < "$OUTPUT_FILE")
    FILE_LINES=$(wc -l < "$OUTPUT_FILE")
    FILE_CONTENT=$(cat "$OUTPUT_FILE")

    # Anti-gaming: check file was created after task started
    FILE_MOD_TIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MOD_TIME" -ge "$START_TIME" ]; then
        FILE_CREATED_DURING_TASK=1
    else
        FILE_CREATED_DURING_TASK=0
    fi
else
    FILE_EXISTS=0
    FILE_SIZE=0
    FILE_LINES=0
    FILE_CONTENT=""
    FILE_CREATED_DURING_TASK=0
fi

# ---- Criterion 1: Water reaction products at Facility Alpha ----

# Acetylene from Calcium Carbide + water
HAS_ACETYLENE=0
echo "$FILE_CONTENT" | grep -qi "acetylene\|C2H2" && HAS_ACETYLENE=1

# Hydrogen from Sodium + water
HAS_HYDROGEN=0
echo "$FILE_CONTENT" | grep -qi "hydrogen gas\|hydrogen is\|H2 gas\|produces hydrogen\|release.*hydrogen\|generat.*hydrogen\|flammable.*hydrogen\|hydrogen.*flammable\|evolve.*hydrogen" && HAS_HYDROGEN=1

# HCl from Phosphorus Trichloride + water
HAS_HCL=0
echo "$FILE_CONTENT" | grep -qi "hydrogen chloride\|HCl gas\|HCl fume\|hydrochloric acid.*gas\|hydrochloric acid.*fume\|produces.*HCl\|generat.*HCl\|release.*HCl" && HAS_HCL=1

# ---- Criterion 2: Cascade reaction — HCl + NaOCl → Cl2 ----

# Chlorine gas as a REACTION PRODUCT (not just listing Chlorine as an inventory item)
HAS_CHLORINE_PRODUCT=0
echo "$FILE_CONTENT" | grep -qi "chlorine gas\|Cl2 gas\|produces chlorine\|generate.*chlorine\|release.*chlorine\|form.*chlorine\|chlorine.*produced\|chlorine.*generated\|chlorine.*released\|toxic chlorine\|liberat.*chlorine" && HAS_CHLORINE_PRODUCT=1

# Mentions hypochlorite in context of the reaction
HAS_HYPOCHLORITE_REACTION=0
echo "$FILE_CONTENT" | grep -qi "hypochlorite.*react\|hypochlorite.*chlorine\|hypochlorite.*HCl\|HCl.*hypochlorite\|bleach.*react\|bleach.*chlorine\|NaOCl.*react\|NaOCl.*chlorine\|NaOCl.*HCl\|HCl.*NaOCl\|acid.*hypochlorite\|hypochlorite.*acid" && HAS_HYPOCHLORITE_REACTION=1

# ---- Criterion 3: HCl + NH3 → NH4Cl aerosol ----
HAS_AMMONIUM_CHLORIDE=0
echo "$FILE_CONTENT" | grep -qi "ammonium chloride\|NH4Cl\|white cloud\|white aerosol\|white fume\|dense.*cloud\|ammonia.*HCl.*react\|HCl.*ammonia.*react\|ammonia.*hydrochloric.*react\|hydrochloric.*ammonia.*react" && HAS_AMMONIUM_CHLORIDE=1

# ---- Criterion 4: ERG / isolation distances ----

# ERG Guide 124 (Chlorine)
HAS_ERG_124=0
echo "$FILE_CONTENT" | grep -qi "guide 124\|ERG 124\|ERG.*124\|guide number.*124" && HAS_ERG_124=1

# Specific protective action distances
HAS_ISOLATION_DISTANCE=0
echo "$FILE_CONTENT" | grep -qi "protective action distance\|isolation.*mile\|evacuat.*mile\|[0-9].*mile\|[0-9].*km\|initial isolation\|downwind.*distance" && HAS_ISOLATION_DISTANCE=1

# Any ERG reference at all
HAS_ANY_ERG=0
echo "$FILE_CONTENT" | grep -qi "ERG\|emergency response guide\|guide number\|guide [0-9]" && HAS_ANY_ERG=1

# ---- Criterion 5: Gamma NaCN + H2SO4 → HCN hazard ----
HAS_HCN=0
echo "$FILE_CONTENT" | grep -qi "hydrogen cyanide\|HCN" && HAS_HCN=1

HAS_GAMMA_CONTEXT=0
echo "$FILE_CONTENT" | grep -qi "sodium cyanide.*sulfuric\|sulfuric.*cyanide\|cyanide.*acid\|facility gamma\|gamma\|electroplating" && HAS_GAMMA_CONTEXT=1

# ---- Criterion 6: Evacuation recommendation ----
HAS_EVACUATION=0
echo "$FILE_CONTENT" | grep -qi "evacuate\|evacuation\|shelter.in.place\|shelter in place\|protective action" && HAS_EVACUATION=1

# ---- Chemical identification counts ----
ALPHA_CHEMICALS=0
echo "$FILE_CONTENT" | grep -qi "calcium carbide" && ALPHA_CHEMICALS=$((ALPHA_CHEMICALS+1))
echo "$FILE_CONTENT" | grep -qi "sodium metal\|sodium (UN\|sodium.*1428\|metallic sodium\|elemental sodium" && ALPHA_CHEMICALS=$((ALPHA_CHEMICALS+1))
echo "$FILE_CONTENT" | grep -qi "phosphorus trichloride\|PCl3\|1809" && ALPHA_CHEMICALS=$((ALPHA_CHEMICALS+1))

BETA_CHEMICALS=0
echo "$FILE_CONTENT" | grep -qi "ammonia\|NH3\|1005" && BETA_CHEMICALS=$((BETA_CHEMICALS+1))
echo "$FILE_CONTENT" | grep -qi "hypochlorite\|NaOCl\|bleach\|1791" && BETA_CHEMICALS=$((BETA_CHEMICALS+1))

GAMMA_CHEMICALS=0
echo "$FILE_CONTENT" | grep -qi "sodium cyanide\|NaCN\|1689" && GAMMA_CHEMICALS=$((GAMMA_CHEMICALS+1))
echo "$FILE_CONTENT" | grep -qi "sulfuric acid\|H2SO4\|1830" && GAMMA_CHEMICALS=$((GAMMA_CHEMICALS+1))

# ---- Write result JSON ----

# Truncate content for JSON safety (first 150 lines)
CONTENT_PREVIEW=$(echo "$FILE_CONTENT" | head -150 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

python3 - <<PYEOF
import json

result = {
    "task": "flood_cascade_hazard_assessment",
    "file_exists": bool($FILE_EXISTS),
    "file_size_bytes": $FILE_SIZE,
    "file_lines": $FILE_LINES,
    "file_created_during_task": bool($FILE_CREATED_DURING_TASK),
    "initial_file_existed": bool($INITIAL_EXISTS),
    "elapsed_seconds": $ELAPSED,

    "has_acetylene": bool($HAS_ACETYLENE),
    "has_hydrogen": bool($HAS_HYDROGEN),
    "has_hcl": bool($HAS_HCL),

    "has_chlorine_product": bool($HAS_CHLORINE_PRODUCT),
    "has_hypochlorite_reaction": bool($HAS_HYPOCHLORITE_REACTION),

    "has_ammonium_chloride": bool($HAS_AMMONIUM_CHLORIDE),

    "has_erg_124": bool($HAS_ERG_124),
    "has_isolation_distance": bool($HAS_ISOLATION_DISTANCE),
    "has_any_erg": bool($HAS_ANY_ERG),

    "has_hcn": bool($HAS_HCN),
    "has_gamma_context": bool($HAS_GAMMA_CONTEXT),

    "has_evacuation": bool($HAS_EVACUATION),

    "alpha_chemicals_found": $ALPHA_CHEMICALS,
    "beta_chemicals_found": $BETA_CHEMICALS,
    "gamma_chemicals_found": $GAMMA_CHEMICALS,

    "content_preview": $CONTENT_PREVIEW
}

with open("/tmp/flood_cascade_hazard_assessment_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/flood_cascade_hazard_assessment_result.json")
PYEOF

echo "=== Export complete ==="
