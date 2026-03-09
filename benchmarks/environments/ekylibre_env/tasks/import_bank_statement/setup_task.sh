#!/bin/bash
echo "=== Setting up Import Bank Statement Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Record initial DB state (count of bank statements)
INITIAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM bank_statements")
echo "${INITIAL_COUNT:-0}" > /tmp/initial_count.txt
echo "Initial bank statement count: ${INITIAL_COUNT:-0}"

# 3. Generate the OFX file with dynamic dates
# Dates need to be recent for the import to make sense contextually
mkdir -p /home/ga/Documents
OFX_FILE="/home/ga/Documents/bank_import.ofx"

DT_NOW=$(date +%Y%m%d000000)
DT_Start=$(date -d "10 days ago" +%Y%m%d000000)
DT_End=$(date -d "tomorrow" +%Y%m%d000000)
DT_T1=$(date -d "5 days ago" +%Y%m%d000000)
DT_T2=$(date -d "3 days ago" +%Y%m%d000000)
DT_T3=$(date -d "1 day ago" +%Y%m%d000000)

cat > "$OFX_FILE" << EOF
OFXHEADER:100
DATA:OFXSGML
VERSION:102
SECURITY:NONE
ENCODING:USASCII
CHARSET:1252
COMPRESSION:NONE
OLDFILEUID:NONE
NEWFILEUID:NONE

<OFX>
<SIGNONMSGSRSV1>
<SONRS>
<STATUS>
<CODE>0
<SEVERITY>INFO
</STATUS>
<DTSERVER>${DT_NOW}
<LANGUAGE>ENG
</SONRS>
</SIGNONMSGSRSV1>
<BANKMSGSRSV1>
<STMTTRNRS>
<TRNUID>1
<STATUS>
<CODE>0
<SEVERITY>INFO
</STATUS>
<STMTRS>
<CURDEF>EUR
<BANKACCTFROM>
<BANKID>12345
<ACCTID>FR761234567890
<ACCTTYPE>CHECKING
</BANKACCTFROM>
<BANKTRANLIST>
<DTSTART>${DT_Start}
<DTEND>${DT_End}
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>${DT_T1}
<TRNAMT>-125.50
<FITID>${DT_T1}001
<NAME>AGRI SUPPLY CO
<MEMO>Small equipment
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>${DT_T2}
<TRNAMT>4500.00
<FITID>${DT_T2}001
<NAME>COOP GRAIN SALES
<MEMO>Wheat delivery
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>${DT_T3}
<TRNAMT>-85.20
<FITID>${DT_T3}001
<NAME>FUEL STATION
<MEMO>Diesel
</STMTTRN>
</BANKTRANLIST>
<LEDGERBAL>
<BALAMT>15000.00
<DTASOF>${DT_End}
</LEDGERBAL>
</STMTRS>
</STMTTRNRS>
</BANKMSGSRSV1>
</OFX>
EOF

chown ga:ga "$OFX_FILE"
chmod 644 "$OFX_FILE"
echo "Generated OFX file at $OFX_FILE"

# 4. Wait for Ekylibre and open Firefox
wait_for_ekylibre 120
EKYLIBRE_URL=$(detect_ekylibre_url)

# Navigate to Bank Statements list
# URL pattern for bank statements index
ensure_firefox_with_ekylibre "${EKYLIBRE_URL}/backend/bank_statements"
sleep 2
maximize_firefox

# 5. Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="