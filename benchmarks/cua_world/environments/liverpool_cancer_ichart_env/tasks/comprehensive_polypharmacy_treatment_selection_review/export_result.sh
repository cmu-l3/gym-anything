#!/system/bin/sh
# Post-task hook: Export UI state for comprehensive_polypharmacy_treatment_selection_review

echo "=== Exporting result for comprehensive_polypharmacy_treatment_selection_review ==="

TASK="treatment_selection"
XML="/sdcard/${TASK}_dump.xml"
RESULT="/sdcard/${TASK}_result.json"

# Allow screen to stabilise
sleep 1

# Capture screenshot for evidence
screencap -p /sdcard/${TASK}_screenshot.png 2>/dev/null

# Dump UI accessibility tree
uiautomator dump "$XML" 2>/dev/null
sleep 1

# Initialise all flags
IBRUTINIB_FOUND=false
VENETOCLAX_FOUND=false
CRIZOTINIB_FOUND=false
KETOCONAZOLE_FOUND=false
FLUCONAZOLE_FOUND=false
VERAPAMIL_FOUND=false
BISOPROLOL_FOUND=false
WARFARIN_FOUND=false
APIXABAN_FOUND=false
SEVERITY_RED=false
SEVERITY_AMBER=false
SEVERITY_GREEN=false
DETAILS_PAGE=false
MECHANISM_FOUND=false

if [ -f "$XML" ]; then
    # Cancer drug names
    grep -qi "ibrutinib" "$XML" && IBRUTINIB_FOUND=true
    grep -qi "venetoclax" "$XML" && VENETOCLAX_FOUND=true
    grep -qi "crizotinib" "$XML" && CRIZOTINIB_FOUND=true

    # Original co-medication names
    grep -qi "ketoconazole" "$XML" && KETOCONAZOLE_FOUND=true
    grep -qi "verapamil" "$XML" && VERAPAMIL_FOUND=true
    grep -qi "warfarin" "$XML" && WARFARIN_FOUND=true

    # Alternative co-medication names
    grep -qi "fluconazole" "$XML" && FLUCONAZOLE_FOUND=true
    grep -qi "bisoprolol" "$XML" && BISOPROLOL_FOUND=true
    grep -qi "apixaban" "$XML" && APIXABAN_FOUND=true

    # Severity indicators
    grep -qi "do not coadminister" "$XML" && SEVERITY_RED=true
    grep -qi "potential interaction\|caution" "$XML" && SEVERITY_AMBER=true
    grep -qi "no interaction expected" "$XML" && SEVERITY_GREEN=true

    # Interaction Details page indicator
    grep -qi "interaction details" "$XML" && DETAILS_PAGE=true

    # Pharmacological mechanism keywords
    grep -qiE "cyp3a4|cyp 3a4|cyp2c9|cyp 2c9|induc|inhibit|exposure|auc|clearance|qt " "$XML" && MECHANISM_FOUND=true
else
    echo "Warning: UI dump not found at $XML"
fi

cat > "$RESULT" << JSONEOF
{
  "ibrutinib_found": $IBRUTINIB_FOUND,
  "venetoclax_found": $VENETOCLAX_FOUND,
  "crizotinib_found": $CRIZOTINIB_FOUND,
  "ketoconazole_found": $KETOCONAZOLE_FOUND,
  "fluconazole_found": $FLUCONAZOLE_FOUND,
  "verapamil_found": $VERAPAMIL_FOUND,
  "bisoprolol_found": $BISOPROLOL_FOUND,
  "warfarin_found": $WARFARIN_FOUND,
  "apixaban_found": $APIXABAN_FOUND,
  "severity_do_not_coadminister": $SEVERITY_RED,
  "severity_potential_interaction": $SEVERITY_AMBER,
  "severity_no_interaction": $SEVERITY_GREEN,
  "on_interaction_details_page": $DETAILS_PAGE,
  "mechanism_text_found": $MECHANISM_FOUND
}
JSONEOF

echo "Result written to $RESULT"
echo "=== Export complete ==="
