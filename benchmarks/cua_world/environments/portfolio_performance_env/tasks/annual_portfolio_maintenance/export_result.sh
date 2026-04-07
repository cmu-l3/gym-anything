#!/bin/bash
echo "=== Exporting annual_portfolio_maintenance results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/managed_portfolio.xml"
RESULT_FILE="/tmp/task_result.json"
TASK_START_MARKER="/tmp/task_start_marker"

# Check file existence
FILE_EXISTS="false"
if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_EXISTS="true"
fi

# Check file modification (was it saved after task start?)
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ] && [ -f "$TASK_START_MARKER" ]; then
    if [ "$PORTFOLIO_FILE" -nt "$TASK_START_MARKER" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Remove stale result file
rm -f "$RESULT_FILE" 2>/dev/null || true

# Parse the portfolio XML and extract all verification data
python3 << PYEOF
import json
import xml.etree.ElementTree as ET
import sys
import os

result = {
    "file_exists": "$FILE_EXISTS" == "true",
    "file_modified": "$FILE_MODIFIED" == "true",
    "split_event_found": False,
    "split_event_date": "",
    "split_ratio_value": 0,
    "dividend_found": False,
    "dividend_date": "",
    "dividend_gross_cents": 0,
    "dividend_tax_cents": 0,
    "taxonomy_found": False,
    "taxonomy_name": "",
    "taxonomy_categories": [],
    "taxonomy_hierarchy": {},
    "taxonomy_assignments": {},
    "app_running": False
}

portfolio_file = "$PORTFOLIO_FILE"

# Check if PP is running
import subprocess
try:
    ps = subprocess.run(["pgrep", "-f", "PortfolioPerformance"], capture_output=True, text=True)
    result["app_running"] = ps.returncode == 0
except:
    pass

if not os.path.exists(portfolio_file):
    with open("$RESULT_FILE", "w") as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

try:
    tree = ET.parse(portfolio_file)
    root = tree.getroot()
except Exception as e:
    result["parse_error"] = str(e)
    with open("$RESULT_FILE", "w") as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

# =============================================
# 1. Check for stock split events on NVIDIA
# =============================================
securities = root.findall(".//securities/security")
nvidia_sec = None
nvidia_idx = -1

for idx, sec in enumerate(securities):
    isin = sec.findtext("isin", "")
    name = sec.findtext("name", "")
    if isin == "US67066G1040" or "NVIDIA" in name.upper() or "NVDA" in name.upper():
        nvidia_sec = sec
        nvidia_idx = idx
        break

if nvidia_sec is not None:
    events_elem = nvidia_sec.find("events")
    if events_elem is not None:
        # Look for any child element that could be a stock split
        for child in events_elem:
            tag_lower = child.tag.lower() if child.tag else ""
            type_text = (child.findtext("type") or "").lower()
            # PP stores stock splits as <stock-split> elements under <events>
            if "split" in tag_lower or "split" in type_text:
                result["split_event_found"] = True
                result["split_event_date"] = child.findtext("date", "")
                raw_val = child.findtext("value", "0")
                try:
                    result["split_ratio_value"] = int(raw_val)
                except:
                    result["split_ratio_value"] = 0
                break

# =============================================
# 2. Check for dividend transactions
# =============================================
accounts = root.findall(".//accounts/account")
for acct in accounts:
    txns_elem = acct.find("transactions")
    if txns_elem is None:
        continue
    for txn in txns_elem:
        txn_type = txn.findtext("type", "")
        if txn_type == "DIVIDENDS":
            txn_date = txn.findtext("date", "")
            # Check if this is a new dividend (not the initial deposit)
            txn_uuid = txn.findtext("uuid", "")
            if txn_uuid == "txn-dep-initial":
                continue

            result["dividend_found"] = True
            result["dividend_date"] = txn_date

            # Extract gross amount and tax from <units>
            gross_cents = 0
            tax_cents = 0
            units_elem = txn.find("units")
            if units_elem is not None:
                for unit in units_elem:
                    unit_type = unit.get("type", "")
                    amt_elem = unit.find("amount")
                    if amt_elem is not None:
                        amt_val = amt_elem.get("amount", "0")
                        try:
                            amt_int = int(amt_val)
                        except:
                            amt_int = 0

                        if unit_type == "GROSS_VALUE":
                            gross_cents = amt_int
                        elif unit_type == "TAX":
                            tax_cents = amt_int

            # If no GROSS_VALUE unit, use the transaction amount as gross
            if gross_cents == 0:
                try:
                    gross_cents = int(txn.findtext("amount", "0"))
                except:
                    gross_cents = 0

            result["dividend_gross_cents"] = gross_cents
            result["dividend_tax_cents"] = tax_cents
            break  # Take the first dividend found

# =============================================
# 3. Check for taxonomy structure
# =============================================
# Build a UUID-to-name map for securities
sec_uuid_map = {}
sec_name_map = {}
for idx, sec in enumerate(securities):
    uuid = sec.findtext("uuid", "")
    name = sec.findtext("name", "")
    sec_uuid_map[uuid] = name
    sec_name_map[f"security[{idx+1}]" if idx > 0 else "security"] = name
    # Also map by simple index reference patterns
    sec_name_map[str(idx)] = name

taxonomies = root.findall(".//taxonomies/taxonomy")
for tax in taxonomies:
    tax_name = tax.findtext("name", "")
    if not tax_name:
        continue

    result["taxonomy_found"] = True
    result["taxonomy_name"] = tax_name

    # Traverse the taxonomy tree to find categories and assignments
    root_elem = tax.find("root")
    if root_elem is None:
        continue

    def traverse_classifications(parent_elem, parent_name=""):
        """Recursively traverse classification tree."""
        children_elem = parent_elem.find("children")
        if children_elem is None:
            return

        for cls in children_elem.findall("classification"):
            cls_name = cls.findtext("name", "")
            if not cls_name:
                continue

            result["taxonomy_categories"].append(cls_name)

            # Record hierarchy: which parent this category belongs to
            if parent_name:
                if parent_name not in result["taxonomy_hierarchy"]:
                    result["taxonomy_hierarchy"][parent_name] = []
                result["taxonomy_hierarchy"][parent_name].append(cls_name)

            # Check assignments in this category
            assignments_elem = cls.find("assignments")
            if assignments_elem is not None:
                for asn in assignments_elem.findall("assignment"):
                    iv = asn.find("investmentVehicle")
                    weight_val = asn.findtext("weight", "0")
                    try:
                        weight_int = int(weight_val)
                    except:
                        weight_int = 0

                    # Try to resolve security name from reference
                    sec_name = "unknown"
                    if iv is not None:
                        ref = iv.get("reference", "")
                        # Try to match UUID in the reference string
                        for uuid, sname in sec_uuid_map.items():
                            if uuid in ref:
                                sec_name = sname
                                break
                        else:
                            # Try index-based resolution
                            # Refs look like ../../../securities/security[N]
                            if "security[" in ref:
                                try:
                                    idx_str = ref.split("security[")[1].split("]")[0]
                                    idx_int = int(idx_str)
                                    if 0 <= idx_int - 1 < len(securities):
                                        sec_name = securities[idx_int - 1].findtext("name", "unknown")
                                except:
                                    pass
                            elif ref.endswith("/security"):
                                # First security (no index = [1])
                                if len(securities) > 0:
                                    sec_name = securities[0].findtext("name", "unknown")

                    if sec_name not in result["taxonomy_assignments"]:
                        result["taxonomy_assignments"][sec_name] = []
                    result["taxonomy_assignments"][sec_name].append({
                        "category": cls_name,
                        "weight": weight_int
                    })

            # Recurse into child classifications
            traverse_classifications(cls, cls_name)

    traverse_classifications(root_elem)
    break  # Take the first taxonomy found

# Write result
with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Ensure result file is readable
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="
