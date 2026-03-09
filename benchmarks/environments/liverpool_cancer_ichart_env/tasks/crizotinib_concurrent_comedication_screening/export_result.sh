#!/system/bin/sh
# Post-task hook: Export UI state for crizotinib_concurrent_comedication_screening

echo "=== Exporting result for crizotinib_concurrent_comedication_screening ==="

TASK="crizotinib_concurrent"
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
CRIZOTINIB_FOUND=false
ACENOCOUMAROL_FOUND=false
FLUCONAZOLE_FOUND=false
ANY_SEVERITY_FOUND=false
SEVERITY_COUNT=0

if [ -f "$XML" ]; then
    grep -qi "crizotinib" "$XML" && CRIZOTINIB_FOUND=true
    grep -qi "acenocoumarol" "$XML" && ACENOCOUMAROL_FOUND=true
    grep -qi "fluconazole" "$XML" && FLUCONAZOLE_FOUND=true
    grep -qi "do not coadminister\|no interaction expected\|potential interaction\|use with caution" "$XML" && ANY_SEVERITY_FOUND=true
    # Count occurrences of any severity banner text (rough estimate of result cards)
    SEVERITY_COUNT=$(grep -oi "do not coadminister\|no interaction expected\|potential interaction\|use with caution" "$XML" 2>/dev/null | wc -l)
else
    echo "Warning: UI dump not found at $XML"
fi

cat > "$RESULT" << JSONEOF
{
  "crizotinib_found": $CRIZOTINIB_FOUND,
  "acenocoumarol_found": $ACENOCOUMAROL_FOUND,
  "fluconazole_found": $FLUCONAZOLE_FOUND,
  "any_severity_found": $ANY_SEVERITY_FOUND,
  "severity_result_count": $SEVERITY_COUNT
}
JSONEOF

echo "Result written to $RESULT"
echo "=== Export complete ==="
