#!/bin/bash
echo "=== Exporting map_b2b_opportunity_relationships results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/map_b2b_opportunity_final.png

# Retrieve IDs of the target records
OPP_ID=$(vtiger_db_query "SELECT potentialid FROM vtiger_potential WHERE potentialname='Cloud Migration Phase 2' ORDER BY potentialid DESC LIMIT 1" | tr -d '[:space:]')
C1_ID=$(vtiger_db_query "SELECT contactid FROM vtiger_contactdetails WHERE firstname='Marcus' AND lastname='Oyelaran' ORDER BY contactid DESC LIMIT 1" | tr -d '[:space:]')
C2_ID=$(vtiger_db_query "SELECT contactid FROM vtiger_contactdetails WHERE firstname='Priya' AND lastname='Chakraborty' ORDER BY contactid DESC LIMIT 1" | tr -d '[:space:]')
DOC_ID=$(vtiger_db_query "SELECT notesid FROM vtiger_notes WHERE title='Cloud Security Addendum' ORDER BY notesid DESC LIMIT 1" | tr -d '[:space:]')
PROD_ID=$(vtiger_db_query "SELECT productid FROM vtiger_products WHERE productname='Enterprise Cloud Server' ORDER BY productid DESC LIMIT 1" | tr -d '[:space:]')

# Check links (Vtiger uses specific pivot tables or the generic crmentityrel table depending on version/module)
C1_LINKED="false"
C2_LINKED="false"
DOC_LINKED="false"
PROD_LINKED="false"

if [ -n "$OPP_ID" ]; then
    # 1. Check Contact 1 (Marcus)
    if [ -n "$C1_ID" ]; then
        C1_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_contpotentialrel WHERE potentialid=$OPP_ID AND contactid=$C1_ID" | tr -d '[:space:]')
        C1_ALT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_crmentityrel WHERE (crmid=$OPP_ID AND relcrmid=$C1_ID) OR (crmid=$C1_ID AND relcrmid=$OPP_ID)" | tr -d '[:space:]')
        if [ "$C1_COUNT" -gt 0 ] || [ "$C1_ALT_COUNT" -gt 0 ]; then C1_LINKED="true"; fi
    fi

    # 2. Check Contact 2 (Priya)
    if [ -n "$C2_ID" ]; then
        C2_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_contpotentialrel WHERE potentialid=$OPP_ID AND contactid=$C2_ID" | tr -d '[:space:]')
        C2_ALT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_crmentityrel WHERE (crmid=$OPP_ID AND relcrmid=$C2_ID) OR (crmid=$C2_ID AND relcrmid=$OPP_ID)" | tr -d '[:space:]')
        if [ "$C2_COUNT" -gt 0 ] || [ "$C2_ALT_COUNT" -gt 0 ]; then C2_LINKED="true"; fi
    fi

    # 3. Check Document
    if [ -n "$DOC_ID" ]; then
        DOC_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_senotesrel WHERE crmid=$OPP_ID AND notesid=$DOC_ID" | tr -d '[:space:]')
        DOC_ALT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_crmentityrel WHERE (crmid=$OPP_ID AND relcrmid=$DOC_ID) OR (crmid=$DOC_ID AND relcrmid=$OPP_ID)" | tr -d '[:space:]')
        if [ "$DOC_COUNT" -gt 0 ] || [ "$DOC_ALT_COUNT" -gt 0 ]; then DOC_LINKED="true"; fi
    fi

    # 4. Check Product
    if [ -n "$PROD_ID" ]; then
        PROD_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_seproductsrel WHERE crmid=$OPP_ID AND productid=$PROD_ID" | tr -d '[:space:]')
        PROD_ALT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_crmentityrel WHERE (crmid=$OPP_ID AND relcrmid=$PROD_ID) OR (crmid=$PROD_ID AND relcrmid=$OPP_ID)" | tr -d '[:space:]')
        if [ "$PROD_COUNT" -gt 0 ] || [ "$PROD_ALT_COUNT" -gt 0 ]; then PROD_LINKED="true"; fi
    fi
fi

# Export to JSON
RESULT_JSON=$(cat << JSONEOF
{
  "opp_id_found": $([ -n "$OPP_ID" ] && echo "true" || echo "false"),
  "links_established": {
    "contact_1_marcus": ${C1_LINKED},
    "contact_2_priya": ${C2_LINKED},
    "document": ${DOC_LINKED},
    "product": ${PROD_LINKED}
  },
  "timestamp": "$(date +%s)"
}
JSONEOF
)

safe_write_result "/tmp/b2b_relationships_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/b2b_relationships_result.json"
echo "$RESULT_JSON"
echo "=== map_b2b_opportunity_relationships export complete ==="