#!/system/bin/sh
# Post-task hook: Export UI state for ibrutinib_comedication_contraindication_screen

echo "=== Exporting result for ibrutinib_comedication_contraindication_screen ==="

TASK="ibrutinib_contraindication"
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
IBRUTINIB_FOUND=false
KETOCONAZOLE_FOUND=false
FLUCONAZOLE_FOUND=false
ACENOCOUMAROL_FOUND=false
SEVERITY_RED=false
DETAILS_PAGE=false
MECHANISM_FOUND=false

if [ -f "$XML" ]; then
    grep -qi "ibrutinib" "$XML" && IBRUTINIB_FOUND=true
    grep -qi "ketoconazole" "$XML" && KETOCONAZOLE_FOUND=true
    grep -qi "fluconazole" "$XML" && FLUCONAZOLE_FOUND=true
    grep -qi "acenocoumarol" "$XML" && ACENOCOUMAROL_FOUND=true
    grep -qi "do not coadminister" "$XML" && SEVERITY_RED=true
    grep -qi "interaction details" "$XML" && DETAILS_PAGE=true
    grep -qi "cyp3a4\|cyp 3a4" "$XML" && MECHANISM_FOUND=true
else
    echo "Warning: UI dump not found at $XML"
fi

# Write result JSON to /sdcard (not /tmp — volatile on Android)
cat > "$RESULT" << JSONEOF
{
  "ibrutinib_found": $IBRUTINIB_FOUND,
  "ketoconazole_found": $KETOCONAZOLE_FOUND,
  "fluconazole_found": $FLUCONAZOLE_FOUND,
  "acenocoumarol_found": $ACENOCOUMAROL_FOUND,
  "severity_do_not_coadminister": $SEVERITY_RED,
  "on_interaction_details_page": $DETAILS_PAGE,
  "mechanism_cyp3a4_found": $MECHANISM_FOUND
}
JSONEOF

echo "Result written to $RESULT"
echo "=== Export complete ==="
