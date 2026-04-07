#!/bin/bash
echo "=== Setting up Provider Enrichment Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Prepare Directories
echo "Creating directories..."
mkdir -p /home/ga/reference
mkdir -p /home/ga/inbound_hl7
mkdir -p /home/ga/outbound_hl7

# Clear any previous data
rm -f /home/ga/inbound_hl7/*
rm -f /home/ga/outbound_hl7/*
rm -f /home/ga/reference/providers.csv

# 2. Generate Real Data (CSV and matching HL7s) using Python
# We generate random data to prevent hardcoding
echo "Generating random provider data and HL7 messages..."
python3 -c '
import csv
import random
import datetime
import os

# Sample names for generation
last_names = ["Smith", "Garcia", "Johnson", "Williams", "Brown", "Jones", "Miller", "Davis"]
first_names = ["James", "Mary", "Robert", "Patricia", "John", "Jennifer", "Michael", "Linda"]

# Generate 5-10 providers
providers = []
for i in range(1, 9):
    pid = f"100{i}"
    lname = random.choice(last_names)
    fname = random.choice(first_names)
    providers.append({"id": pid, "last": lname, "first": fname})

# Write CSV
csv_path = "/home/ga/reference/providers.csv"
with open(csv_path, "w", newline="") as f:
    writer = csv.writer(f)
    # Header is important for some parsing logic, though task implies simple CSV
    writer.writerow(["ProviderID", "LastName", "FirstName"])
    for p in providers:
        writer.writerow([p["id"], p["last"], p["first"]])

print(f"Generated {len(providers)} providers in {csv_path}")

# Generate HL7 Messages for these providers
# We only put the ID in PV1-7.1. The agent must fill 7.2 and 7.3
hl7_template = "MSH|^~\\&|HIS|HOSP|LIMS|LAB|{ts}||ADT^A01|MSG{msgid}|P|2.3\rEVN|A01|{ts}\rPID|1||MRN{mrn}||Test^Patient{i}||19800101|M\rPV1|1|O|Loc|||{prov_id}^^^|||||||||||||||||||||||||||||||||||||20240101"

inbound_dir = "/home/ga/inbound_hl7"
for i, p in enumerate(providers):
    ts = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    # Randomly select a provider for this message
    prov = p # One message per provider for verification coverage
    
    msg = hl7_template.format(
        ts=ts, 
        msgid=f"{i+1:05d}", 
        mrn=f"999{i}", 
        i=i, 
        prov_id=prov["id"]
    )
    
    filename = os.path.join(inbound_dir, f"msg_{prov['id']}.hl7")
    with open(filename, "w") as f:
        f.write(msg)

print(f"Generated {len(providers)} HL7 messages in {inbound_dir}")
'

# Set permissions so agent can read/write
chown -R ga:ga /home/ga/reference /home/ga/inbound_hl7 /home/ga/outbound_hl7
chmod -R 777 /home/ga/reference /home/ga/inbound_hl7 /home/ga/outbound_hl7

# 3. Open Terminal for Agent
# We open a terminal with instructions and useful paths
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "======================================================="
echo " NextGen Connect - Global Map CSV Enrichment Task"
echo "======================================================="
echo ""
echo "GOAL: Enrich HL7 PV1-7 (Provider) using a cached CSV map."
echo ""
echo "Files:"
echo "  Source HL7s:    /home/ga/inbound_hl7/"
echo "  Reference CSV:  /home/ga/reference/providers.csv"
echo "  Output Dir:     /home/ga/outbound_hl7/"
echo ""
echo "Pattern Requirement:"
echo "  1. Read CSV in DEPLOY SCRIPT -> Put in Global Channel Map"
echo "  2. Read Global Map in TRANSFORMER -> Update PV1-7"
echo ""
echo "Reference CSV Format:"
echo "  ProviderID,LastName,FirstName"
echo ""
echo "API: https://localhost:8443/api (admin/admin)"
echo "     Header: X-Requested-With: OpenAPI"
echo ""
echo "======================================================="
echo ""
exec bash
' 2>/dev/null &

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="