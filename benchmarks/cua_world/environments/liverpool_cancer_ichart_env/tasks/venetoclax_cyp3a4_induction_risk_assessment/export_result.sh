#!/system/bin/sh
# Post-task hook: Export UI state for venetoclax_cyp3a4_induction_risk_assessment

echo "=== Exporting result for venetoclax_cyp3a4_induction_risk_assessment ==="

TASK="venetoclax_induction"
XML="/sdcard/${TASK}_dump.xml"
RESULT="/sdcard/${TASK}_result.json"

# Allow screen to stabilise
sleep 1

# Capture screenshot for evidence
screencap -p /sdcard/${TASK}_screenshot.png 2>/dev/null

# Dump UI accessibility tree
uiautomator dump "$XML" 2>/dev/null
sleep 1

# Initialise flags
VENETOCLAX_FOUND=false
CARBAMAZEPINE_FOUND=false
WARFARIN_FOUND=false
FLUCONAZOLE_FOUND=false
SEVERITY_RED=false
DETAILS_PAGE=false
MECHANISM_FOUND=false

if [ -f "$XML" ]; then
    grep -qi "venetoclax" "$XML" && VENETOCLAX_FOUND=true
    grep -qi "carbamazepine" "$XML" && CARBAMAZEPINE_FOUND=true
    grep -qi "warfarin" "$XML" && WARFARIN_FOUND=true
    grep -qi "fluconazole" "$XML" && FLUCONAZOLE_FOUND=true
    grep -qi "do not coadminister" "$XML" && SEVERITY_RED=true
    grep -qi "interaction details" "$XML" && DETAILS_PAGE=true
    grep -qi "cyp3a4\|cyp 3a4\|induc\|exposure\|auc" "$XML" && MECHANISM_FOUND=true
else
    echo "Warning: UI dump not found at $XML"
fi

cat > "$RESULT" << JSONEOF
{
  "venetoclax_found": $VENETOCLAX_FOUND,
  "carbamazepine_found": $CARBAMAZEPINE_FOUND,
  "warfarin_found": $WARFARIN_FOUND,
  "fluconazole_found": $FLUCONAZOLE_FOUND,
  "severity_do_not_coadminister": $SEVERITY_RED,
  "on_interaction_details_page": $DETAILS_PAGE,
  "mechanism_text_found": $MECHANISM_FOUND
}
JSONEOF

echo "Result written to $RESULT"
echo "=== Export complete ==="
