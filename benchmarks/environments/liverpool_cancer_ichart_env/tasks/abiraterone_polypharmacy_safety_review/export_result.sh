#!/system/bin/sh
# Post-task hook: Export UI state for abiraterone_polypharmacy_safety_review

echo "=== Exporting result for abiraterone_polypharmacy_safety_review ==="

TASK="abiraterone_polypharmacy"
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
ABIRATERONE_FOUND=false
KETOCONAZOLE_FOUND=false
WARFARIN_FOUND=false
ACENOCOUMAROL_FOUND=false
SEVERITY_RED=false
DETAILS_PAGE=false
MECHANISM_FOUND=false

if [ -f "$XML" ]; then
    grep -qi "abiraterone" "$XML" && ABIRATERONE_FOUND=true
    grep -qi "ketoconazole" "$XML" && KETOCONAZOLE_FOUND=true
    grep -qi "warfarin" "$XML" && WARFARIN_FOUND=true
    grep -qi "acenocoumarol" "$XML" && ACENOCOUMAROL_FOUND=true
    grep -qi "do not coadminister" "$XML" && SEVERITY_RED=true
    grep -qi "interaction details" "$XML" && DETAILS_PAGE=true
    grep -qi "cyp17\|cyp 17\|cyp3a4\|cyp 3a4\|androgen" "$XML" && MECHANISM_FOUND=true
else
    echo "Warning: UI dump not found at $XML"
fi

cat > "$RESULT" << JSONEOF
{
  "abiraterone_found": $ABIRATERONE_FOUND,
  "ketoconazole_found": $KETOCONAZOLE_FOUND,
  "warfarin_found": $WARFARIN_FOUND,
  "acenocoumarol_found": $ACENOCOUMAROL_FOUND,
  "severity_do_not_coadminister": $SEVERITY_RED,
  "on_interaction_details_page": $DETAILS_PAGE,
  "mechanism_text_found": $MECHANISM_FOUND
}
JSONEOF

echo "Result written to $RESULT"
echo "=== Export complete ==="
