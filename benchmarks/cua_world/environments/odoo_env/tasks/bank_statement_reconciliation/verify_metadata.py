#!/usr/bin/env python3
"""Verify metadata claims from task.json"""

import json
import re

# Read task.json
with open('task.json') as f:
    task = json.load(f)

# Read setup_task.sh
with open('setup_task.sh') as f:
    setup_script = f.read()

metadata = task.get('metadata', {})

# Extract the bank statement file content from setup script
statement_match = re.search(r"cat > (.+?) << 'EOF'(.*?)EOF", setup_script, re.DOTALL)
statement_file = None
statement_content = None
if statement_match:
    statement_file = statement_match.group(1)
    statement_content = statement_match.group(2)

# Parse the statement to verify claims
transactions = []
fee_amount = None
starting_balance = None
ending_balance = None

if statement_content:
    for line in statement_content.split('\n'):
        if 'Bank Service Fee' in line:
            match = re.search(r'[-]?(\d+,?\d*\.\d+)', line)
            if match:
                fee_amount = float(match.group(1).replace(',', ''))
        if 'Payment received:' in line:
            match = re.search(r'([A-Za-z\s]+)\s*\|\s*[+]?(\d+,?\d*\.\d+)', line)
            if match:
                transactions.append({
                    'type': 'incoming',
                    'partner': match.group(1).strip(),
                    'amount': float(match.group(2).replace(',', ''))
                })
        if 'Payment to:' in line:
            match = re.search(r'([A-Za-z\s]+)\s*\|\s*[-]?(\d+,?\d*\.\d+)', line)
            if match:
                transactions.append({
                    'type': 'outgoing',
                    'partner': match.group(1).strip(),
                    'amount': float(match.group(2).replace(',', ''))
                })
        if 'Starting Balance:' in line:
            match = re.search(r'(\d+,?\d*\.\d+)', line)
            if match:
                starting_balance = float(match.group(1).replace(',', ''))
        if 'Ending Balance:' in line:
            match = re.search(r'(\d+,?\d*\.\d+)', line)
            if match:
                ending_balance = float(match.group(1).replace(',', ''))

# Extract partners from setup script
partners_match = re.findall(r"'name':\s*'([^']+)'.*?'customer_rank':\s*(\d+).*?'supplier_rank':\s*(\d+)", setup_script)

print("=== METADATA VERIFICATION ===\n")
print("1. statement_file claim:")
print(f"   Claimed: {metadata.get('statement_file')}")
print(f"   Found in script: {statement_file}")
print(f"   MATCH: {metadata.get('statement_file') == statement_file}\n")

print("2. expected_fee_amount claim:")
print(f"   Claimed: {metadata.get('expected_fee_amount')}")
print(f"   Found in statement: {fee_amount}")
print(f"   MATCH: {metadata.get('expected_fee_amount') == fee_amount}\n")

print("3. Transaction count verification:")
incoming = [t for t in transactions if t['type'] == 'incoming']
outgoing = [t for t in transactions if t['type'] == 'outgoing']
print(f"   Incoming transactions: {len(incoming)} (claimed: 2)")
print(f"   Outgoing transactions: {len(outgoing)} (claimed: 2)")
print(f"   Bank fees: 1 (claimed: 1)")
print(f"   Total: {len(transactions) + 1} (claimed: 5)\n")

print("4. customers list verification:")
print(f"   Claimed: {metadata.get('customers')}")
customer_names = [t['partner'] for t in transactions if t['type'] == 'incoming']
print(f"   Found in statement: {customer_names}")
print(f"   MATCH: {set(metadata.get('customers', [])) == set(customer_names)}\n")

print("5. vendors list verification:")
print(f"   Claimed: {metadata.get('vendors')}")
vendor_names = [t['partner'] for t in transactions if t['type'] == 'outgoing']
print(f"   Found in statement: {vendor_names}")
print(f"   MATCH: {set(metadata.get('vendors', [])) == set(vendor_names)}\n")

print("6. Balance verification:")
print(f"   Starting Balance: {starting_balance}")
calc_balance = starting_balance
for t in transactions:
    if t['type'] == 'incoming':
        calc_balance += t['amount']
    else:
        calc_balance -= t['amount']
calc_balance -= fee_amount
print(f"   Calculated ending balance: {calc_balance}")
print(f"   Statement ending balance: {ending_balance}")
print(f"   MATCH: {abs(calc_balance - ending_balance) < 0.01}\n")

print("7. Data source:")
print("   The data is created SYNTHETICALLY in setup_task.sh via Odoo XML-RPC")
print("   NOT from an external data source")
