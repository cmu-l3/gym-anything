#!/bin/bash
echo "=== Exporting record_buy_transaction result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

INITIAL_TXN_COUNT=$(cat /tmp/initial_txn_count 2>/dev/null | tr -d '[:space:]' || echo "0")
[ -z "$INITIAL_TXN_COUNT" ] && INITIAL_TXN_COUNT="0"
PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/trading_portfolio.xml"

# Also check for auto-saved files
LATEST_FILE=$(find /home/ga -maxdepth 4 \( -name "*.xml" -o -name "*.portfolio" \) -newer /tmp/task_start_marker -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
if [ -n "$LATEST_FILE" ] && [ -f "$LATEST_FILE" ]; then
    PORTFOLIO_FILE="$LATEST_FILE"
fi

# Analyze the portfolio XML for new MSFT buy transaction
python3 << PYEOF > /tmp/txn_analysis.json
import xml.etree.ElementTree as ET
import json

result = {
    "portfolio_found": False,
    "file_modified": False,
    "total_portfolio_txns": 0,
    "msft_buy_found": False,
    "msft_buy_date": "",
    "msft_buy_shares": 0,
    "msft_buy_amount": 0,
    "msft_buy_fees": 0,
    "new_txn_count": 0,
    "all_txns": []
}

portfolio_file = "$PORTFOLIO_FILE"

try:
    import os
    if os.path.exists(portfolio_file):
        result["portfolio_found"] = True

        # Check modification time
        import time
        marker_time = os.path.getmtime("/tmp/task_start_marker") if os.path.exists("/tmp/task_start_marker") else 0
        file_time = os.path.getmtime(portfolio_file)
        result["file_modified"] = file_time > marker_time

        tree = ET.parse(portfolio_file)
        root = tree.getroot()

        # Find MSFT security reference
        msft_uuid = None
        sec_index = -1
        securities_elem = root.find("securities")
        security_list = securities_elem.findall("security") if securities_elem is not None else []
        for i, sec in enumerate(security_list):
            name = sec.find("name")
            ticker = sec.find("tickerSymbol")
            if name is not None and ("Microsoft" in (name.text or "") or
                (ticker is not None and ticker.text == "MSFT")):
                msft_uuid = sec.find("uuid")
                sec_index = i
                break

        # Count and analyze portfolio transactions
        # PP crossEntry format nests the real portfolio inside account-transaction
        # root.iter("portfolio") may find both the real one and a reference one
        # Accumulate counts across all portfolio elements
        all_portfolio_txns = []
        for portfolio in root.iter("portfolio"):
            txns = portfolio.findall(".//portfolio-transaction")
            all_portfolio_txns.extend(txns)

        result["total_portfolio_txns"] = len(all_portfolio_txns)
        result["new_txn_count"] = len(all_portfolio_txns) - int("$INITIAL_TXN_COUNT".strip())

        for txn in all_portfolio_txns:
            txn_type = txn.find("type")
            txn_date = txn.find("date")
            txn_amount = txn.find("amount")
            txn_shares = txn.find("shares")
            txn_security = txn.find("security")

            txn_info = {
                "type": txn_type.text if txn_type is not None else "",
                "date": txn_date.text if txn_date is not None else "",
                "amount_raw": int(txn_amount.text) if txn_amount is not None else 0,
                "shares_raw": int(txn_shares.text) if txn_shares is not None else 0,
            }
            # Convert from internal units
            txn_info["amount_usd"] = txn_info["amount_raw"] / 100.0
            txn_info["shares"] = txn_info["shares_raw"] / 1000000000.0

            # Check fees
            for unit in txn.findall(".//unit"):
                if unit.get("type") == "FEE":
                    fee_amt = unit.find("amount")
                    if fee_amt is not None:
                        txn_info["fees"] = int(fee_amt.get("amount", "0")) / 100.0

            result["all_txns"].append(txn_info)

            # Check if this is a MSFT buy
            if txn_type is not None and txn_type.text == "BUY":
                # Check if security reference points to MSFT
                is_msft = False
                if txn_security is not None:
                    ref = txn_security.get("reference", "")
                    if "security[2]" in ref or (sec_index >= 0 and f"security[{sec_index+1}]" in ref):
                        is_msft = True
                    elif sec_index == 0 and "security" in ref and "[" not in ref:
                        is_msft = False  # This is first security (AAPL)
                    # Also check by UUID reference
                    if msft_uuid is not None and ref == msft_uuid.text:
                        is_msft = True

                if is_msft and "2024-04-15" in txn_info.get("date", ""):
                    result["msft_buy_found"] = True
                    result["msft_buy_date"] = txn_info["date"]
                    result["msft_buy_shares"] = txn_info["shares"]
                    result["msft_buy_amount"] = txn_info["amount_usd"]
                    result["msft_buy_fees"] = txn_info.get("fees", 0)

except Exception as e:
    result["parse_error"] = str(e)

with open("/tmp/txn_analysis.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Create final result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cp /tmp/txn_analysis.json "$TEMP_JSON"

rm -f /tmp/buy_txn_result.json 2>/dev/null || sudo rm -f /tmp/buy_txn_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/buy_txn_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/buy_txn_result.json
chmod 666 /tmp/buy_txn_result.json 2>/dev/null || sudo chmod 666 /tmp/buy_txn_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/buy_txn_result.json"
cat /tmp/buy_txn_result.json
echo "=== Export complete ==="
