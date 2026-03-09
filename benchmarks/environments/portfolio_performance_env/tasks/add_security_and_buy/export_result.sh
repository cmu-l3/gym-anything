#!/bin/bash
echo "=== Exporting add_security_and_buy result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

INITIAL_SEC_COUNT=$(cat /tmp/initial_sec_count 2>/dev/null | tr -d '[:space:]' || echo "0")
[ -z "$INITIAL_SEC_COUNT" ] && INITIAL_SEC_COUNT="0"
INITIAL_TXN_COUNT=$(cat /tmp/initial_txn_count 2>/dev/null | tr -d '[:space:]' || echo "0")
[ -z "$INITIAL_TXN_COUNT" ] && INITIAL_TXN_COUNT="0"
PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/growth_portfolio.xml"

# Check for recently modified files
LATEST_FILE=$(find /home/ga -maxdepth 4 \( -name "*.xml" -o -name "*.portfolio" \) -newer /tmp/task_start_marker -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
if [ -n "$LATEST_FILE" ] && [ -f "$LATEST_FILE" ]; then
    PORTFOLIO_FILE="$LATEST_FILE"
fi

python3 << PYEOF > /tmp/security_buy_analysis.json
import xml.etree.ElementTree as ET
import json
import os

result = {
    "portfolio_found": False,
    "file_modified": False,
    "initial_sec_count": int("$INITIAL_SEC_COUNT".strip()),
    "initial_txn_count": int("$INITIAL_TXN_COUNT".strip()),
    "current_sec_count": 0,
    "current_txn_count": 0,
    "googl_security_found": False,
    "googl_name": "",
    "googl_ticker": "",
    "googl_isin": "",
    "googl_currency": "",
    "googl_buy_found": False,
    "googl_buy_date": "",
    "googl_buy_shares": 0,
    "googl_buy_amount": 0,
    "googl_buy_fees": 0,
    "all_securities": [],
    "all_txns": []
}

portfolio_file = "$PORTFOLIO_FILE"

try:
    if os.path.exists(portfolio_file):
        result["portfolio_found"] = True

        marker_time = os.path.getmtime("/tmp/task_start_marker") if os.path.exists("/tmp/task_start_marker") else 0
        file_time = os.path.getmtime(portfolio_file)
        result["file_modified"] = file_time > marker_time

        tree = ET.parse(portfolio_file)
        root = tree.getroot()

        # Enumerate securities (only direct children of <securities> element)
        securities_elem = root.find("securities")
        securities = list(securities_elem.findall("security")) if securities_elem is not None else []
        result["current_sec_count"] = len(securities)

        googl_sec_index = -1
        for i, sec in enumerate(securities):
            name = sec.find("name")
            ticker = sec.find("tickerSymbol")
            isin = sec.find("isin")
            currency = sec.find("currencyCode")

            sec_info = {
                "name": name.text if name is not None else "",
                "ticker": ticker.text if ticker is not None else "",
                "isin": isin.text if isin is not None else "",
                "currency": currency.text if currency is not None else ""
            }
            result["all_securities"].append(sec_info)

            # Check for Alphabet/GOOGL
            name_text = (name.text or "").lower() if name is not None else ""
            ticker_text = (ticker.text or "").upper() if ticker is not None else ""
            isin_text = (isin.text or "") if isin is not None else ""

            if "alphabet" in name_text or "googl" in name_text or \
               ticker_text == "GOOGL" or ticker_text == "GOOG" or \
               isin_text == "US02079K3059":
                result["googl_security_found"] = True
                result["googl_name"] = sec_info["name"]
                result["googl_ticker"] = sec_info["ticker"]
                result["googl_isin"] = sec_info["isin"]
                result["googl_currency"] = sec_info["currency"]
                googl_sec_index = i

        # Enumerate portfolio transactions
        # PP crossEntry format nests the real portfolio inside account-transaction
        # root.iter("portfolio") may find both the real one and a reference one
        # Accumulate counts across all portfolio elements
        all_portfolio_txns = []
        for portfolio in root.iter("portfolio"):
            txns = portfolio.findall(".//portfolio-transaction")
            all_portfolio_txns.extend(txns)

        result["current_txn_count"] = len(all_portfolio_txns)

        for txn in all_portfolio_txns:
            txn_type = txn.find("type")
            txn_date = txn.find("date")
            txn_amount = txn.find("amount")
            txn_shares = txn.find("shares")
            txn_security = txn.find("security")

            txn_info = {
                "type": txn_type.text if txn_type is not None else "",
                "date": txn_date.text if txn_date is not None else "",
                "amount_usd": (int(txn_amount.text) / 100.0) if txn_amount is not None else 0,
                "shares": (int(txn_shares.text) / 1000000000.0) if txn_shares is not None else 0,
                "fees": 0
            }

            for unit in txn.findall(".//unit"):
                if unit.get("type") == "FEE":
                    fee_amt = unit.find("amount")
                    if fee_amt is not None:
                        txn_info["fees"] = int(fee_amt.get("amount", "0")) / 100.0

            result["all_txns"].append(txn_info)

            # Check if this is a GOOGL buy
            if txn_type is not None and txn_type.text == "BUY" and googl_sec_index >= 0:
                is_googl = False
                if txn_security is not None:
                    ref = txn_security.get("reference", "")
                    if googl_sec_index == 0 and "security" in ref and "[" not in ref:
                        is_googl = True
                    elif f"security[{googl_sec_index+1}]" in ref:
                        is_googl = True

                if is_googl:
                    result["googl_buy_found"] = True
                    result["googl_buy_date"] = txn_info["date"]
                    result["googl_buy_shares"] = txn_info["shares"]
                    result["googl_buy_amount"] = txn_info["amount_usd"]
                    result["googl_buy_fees"] = txn_info["fees"]

except Exception as e:
    result["parse_error"] = str(e)

with open("/tmp/security_buy_analysis.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cp /tmp/security_buy_analysis.json "$TEMP_JSON"

rm -f /tmp/add_security_buy_result.json 2>/dev/null || sudo rm -f /tmp/add_security_buy_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_security_buy_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_security_buy_result.json
chmod 666 /tmp/add_security_buy_result.json 2>/dev/null || sudo chmod 666 /tmp/add_security_buy_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/add_security_buy_result.json"
cat /tmp/add_security_buy_result.json
echo "=== Export complete ==="
