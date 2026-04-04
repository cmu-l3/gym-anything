#!/system/bin/sh
# Post-task hook: Export UI state for olaparib_antiepileptic_interaction_consultation

echo "=== Exporting result for olaparib_antiepileptic_interaction_consultation ==="

TASK="olaparib_antiepileptic"
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
OLAPARIB_FOUND=false
CARBAMAZEPINE_FOUND=false
WARFARIN_FOUND=false
ACENOCOUMAROL_FOUND=false
SEVERITY_RED=false
DETAILS_PAGE=false
MECHANISM_FOUND=false

if [ -f "$XML" ]; then
    grep -qi "olaparib" "$XML" && OLAPARIB_FOUND=true
    grep -qi "carbamazepine" "$XML" && CARBAMAZEPINE_FOUND=true
    grep -qi "warfarin" "$XML" && WARFARIN_FOUND=true
    grep -qi "acenocoumarol" "$XML" && ACENOCOUMAROL_FOUND=true
    grep -qi "do not coadminister" "$XML" && SEVERITY_RED=true
    grep -qi "interaction details" "$XML" && DETAILS_PAGE=true
    grep -qi "cyp3a4\|cyp 3a4\|induc\|auc\|exposure\|plasma" "$XML" && MECHANISM_FOUND=true
else
    echo "Warning: UI dump not found at $XML"
fi

cat > "$RESULT" << JSONEOF
{
  "olaparib_found": $OLAPARIB_FOUND,
  "carbamazepine_found": $CARBAMAZEPINE_FOUND,
  "warfarin_found": $WARFARIN_FOUND,
  "acenocoumarol_found": $ACENOCOUMAROL_FOUND,
  "severity_do_not_coadminister": $SEVERITY_RED,
  "on_interaction_details_page": $DETAILS_PAGE,
  "mechanism_text_found": $MECHANISM_FOUND
}
JSONEOF

echo "Result written to $RESULT"
echo "=== Export complete ==="
