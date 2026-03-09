#!/bin/bash
echo "=== Exporting record_drip_transaction result ==="

# 1. Capture final screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Define paths
PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio"
DIVIDEND_FILE="$PORTFOLIO_DIR/dividendsummary.csv"
BUY_FILE="$PORTFOLIO_DIR/buyportfolio.csv"

# 4. Check file modification times (Anti-gaming)
DIV_MODIFIED="false"
BUY_MODIFIED="false"

if [ -f "$DIVIDEND_FILE" ]; then
    DIV_MTIME=$(stat -c %Y "$DIVIDEND_FILE" 2>/dev/null || echo "0")
    if [ "$DIV_MTIME" -gt "$TASK_START" ]; then DIV_MODIFIED="true"; fi
fi

if [ -f "$BUY_FILE" ]; then
    BUY_MTIME=$(stat -c %Y "$BUY_FILE" 2>/dev/null || echo "0")
    if [ "$BUY_MTIME" -gt "$TASK_START" ]; then BUY_MODIFIED="true"; fi
fi

# 5. Parse CSV files using Python for reliability
# We extract the specific rows added by the agent
python3 << PYEOF > /tmp/parsed_data.json
import csv
import json
import os
import sys

result = {
    "dividend_found": False,
    "dividend_details": {},
    "buy_found": False,
    "buy_details": {},
    "original_count": 0,
    "current_count": 0,
    "original_preserved": False
}

div_file = "$DIVIDEND_FILE"
buy_file = "$BUY_FILE"

# Parse Dividend File
if os.path.exists(div_file):
    try:
        with open(div_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            # Filter for AAPL dividends
            aapl_divs = [r for r in rows if 'AAPL' in r.get('Code', '') or 'AAPL' in r.get('Symbol', '')]
            if aapl_divs:
                # Get the last one added
                last_div = aapl_divs[-1]
                result["dividend_found"] = True
                result["dividend_details"] = {
                    "date": last_div.get('Date', ''),
                    "amount": last_div.get('Amount', '0')
                }
    except Exception as e:
        print(f"Error reading dividend file: {e}", file=sys.stderr)

# Parse Buy Portfolio File
if os.path.exists(buy_file):
    try:
        with open(buy_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            result["current_count"] = len(rows)
            
            # Check original holdings (AAPL 100, MSFT 50, NVDA 25)
            originals_ok = 0
            for r in rows:
                code = r.get('Code', '')
                units = r.get('Units', '0')
                if code == 'AAPL' and float(units) == 100.0: originals_ok += 1
                if code == 'MSFT' and float(units) == 50.0: originals_ok += 1
                if code == 'NVDA' and float(units) == 25.0: originals_ok += 1
            
            if originals_ok >= 3:
                result["original_preserved"] = True

            # Find the new DRIP buy
            # Look for AAPL with units roughly 0.55
            drip_buys = []
            for r in rows:
                if 'AAPL' in r.get('Code', '') or 'AAPL' in r.get('Symbol', ''):
                    try:
                        u = float(r.get('Units', '0'))
                        if 0.5 <= u <= 0.6: # loose filter for candidate
                            drip_buys.append(r)
                    except:
                        pass
            
            if drip_buys:
                last_buy = drip_buys[-1]
                result["buy_found"] = True
                result["buy_details"] = {
                    "date": last_buy.get('Date', ''),
                    "units": last_buy.get('Units', '0'),
                    "price": last_buy.get('Purchase Price', '0'),
                    "comment": last_buy.get('Comment', '')
                }

    except Exception as e:
        print(f"Error reading buy file: {e}", file=sys.stderr)

print(json.dumps(result))
PYEOF

# 6. Create final result JSON
# Merge bash state checks with python parsed data
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
PARSED_JSON=$(cat /tmp/parsed_data.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "div_file_modified": $DIV_MODIFIED,
    "buy_file_modified": $BUY_MODIFIED,
    "screenshot_path": "/tmp/task_final.png",
    "data": $PARSED_JSON
}
EOF

# 7. Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"
rm -f /tmp/parsed_data.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="