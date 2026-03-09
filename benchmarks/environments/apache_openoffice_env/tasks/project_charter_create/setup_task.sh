#!/bin/bash
set -e

echo "=== Setting up Project Charter Create Task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare directories
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/Ridgeline_DC_Migration_Charter.odt 2>/dev/null || true
rm -f /home/ga/Documents/project_data.json 2>/dev/null || true

# 3. Create the Project Data JSON file
cat > /home/ga/Documents/project_data.json << 'EOF'
{
  "document": {
    "number": "RFS-PMO-2024-017",
    "title": "Enterprise Data Center Migration to Cloud Infrastructure",
    "version": "1.0",
    "date": "2024-03-18",
    "classification": "Internal - Confidential"
  },
  "company": {
    "name": "Ridgeline Financial Services, Inc.",
    "address": "100 Constitution Plaza, Suite 1800, Hartford, CT 06103",
    "industry": "Financial Services - Insurance & Wealth Management"
  },
  "project_sponsor": { "name": "Elena Marchetti", "title": "Chief Financial Officer" },
  "project_manager": { "name": "Yuki Tanaka", "title": "Senior Project Manager" },
  "business_case": "Ridgeline's primary data center lease at the Markley Group Hartford colocation facility expires September 2025. The current on-premises infrastructure (280 physical servers, 1,400 virtual machines) is aging, with 40% of hardware past end-of-life. A TCO analysis projects $1.4M annual savings by Year 3 post-migration. The migration also addresses regulatory findings from the 2023 CT Department of Banking examination regarding disaster recovery capabilities.",
  "objectives": [
    { "id": "OBJ-1", "description": "Migrate 100% of production workloads to AWS US-East-1 by July 2025" },
    { "id": "OBJ-2", "description": "Establish multi-region disaster recovery in US-West-2 with RPO < 1 hour" },
    { "id": "OBJ-3", "description": "Achieve SOC 2 Type II and PCI DSS 4.0 compliance for cloud environment" }
  ],
  "scope": {
    "in_scope": [
      "Migration of 1,400 VMs and 320 TB storage to AWS",
      "Network architecture redesign including Direct Connect",
      "Database migration for Oracle, PostgreSQL, and SQL Server",
      "Decommissioning of Hartford colocation facility"
    ],
    "out_of_scope": [
      "End-user desktop/laptop hardware refresh",
      "Salesforce CRM migration (already SaaS)",
      "Office 365 tenant changes"
    ]
  },
  "stakeholders": [
    { "name": "Elena Marchetti", "role": "Sponsor", "dept": "Executive", "responsibility": "Budget authority, Steering Committee Chair" },
    { "name": "David Okafor", "role": "CTO", "dept": "Technology", "responsibility": "Technical authority and architecture approval" },
    { "name": "Thomas Lindström", "role": "CISO", "dept": "Security", "responsibility": "Security architecture and compliance validation" },
    { "name": "Rachel Dominguez", "role": "VP Infra", "dept": "IT Ops", "responsibility": "Migration planning and execution lead" }
  ],
  "milestones": [
    { "name": "Assessment Complete", "date": "2024-06-30", "deliverable": "Cloud Readiness Report & Migration Runbook" },
    { "name": "AWS Landing Zone Ready", "date": "2024-09-15", "deliverable": "Production AWS environment operational" },
    { "name": "Non-Prod Migration", "date": "2025-01-31", "deliverable": "Dev/Staging workloads migrated" },
    { "name": "Production Cutover", "date": "2025-07-31", "deliverable": "All production workloads live in AWS" },
    { "name": "DC Decommission", "date": "2025-09-30", "deliverable": "Hartford facility vacated" }
  ],
  "budget": {
    "total_usd": 4200000,
    "items": [
      { "category": "Cloud Infrastructure", "amount": 1680000, "notes": "AWS Reserved Instances & Storage (18 mo)" },
      { "category": "Professional Services", "amount": 1050000, "notes": "Migration partners & Audit firms" },
      { "category": "Security & Compliance", "amount": 525000, "notes": "Tooling licensing & Pen testing" },
      { "category": "Internal Labor", "amount": 630000, "notes": "Staff overtime & backfill" },
      { "category": "Contingency", "amount": 315000, "notes": "7.5% reserve" }
    ]
  },
  "risks": [
    { "id": "R-01", "risk": "Data sovereignty non-compliance", "prob": "Low", "impact": "High", "mitigation": "Compliance team mapping of all data classes before replication" },
    { "id": "R-02", "risk": "Direct Connect provisioning delays", "prob": "High", "impact": "Medium", "mitigation": "Order circuits in Month 1; use VPN as interim" },
    { "id": "R-03", "risk": "Application compatibility failure", "prob": "Medium", "impact": "High", "mitigation": "Pre-migration testing in staging; 72hr rollback window" }
  ]
}
EOF
chown ga:ga /home/ga/Documents/project_data.json

# 4. Record initial state
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists.txt

# 5. Ensure OpenOffice Writer is available via desktop shortcut
if [ ! -f /home/ga/Desktop/OpenOffice-Writer.desktop ]; then
    cat > /home/ga/Desktop/OpenOffice-Writer.desktop << DESKTOPEOF
[Desktop Entry]
Name=OpenOffice Writer
Comment=Apache OpenOffice Word Processor
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=openoffice4-writer
Terminal=false
Type=Application
Categories=Office;WordProcessor;
DESKTOPEOF
    chown ga:ga /home/ga/Desktop/OpenOffice-Writer.desktop
    chmod +x /home/ga/Desktop/OpenOffice-Writer.desktop
fi

# 6. Launch Writer to blank state (optional, but helps agent start faster)
# The agent is expected to create a NEW document, so starting with a blank one is helpful
if ! pgrep -f "soffice" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    sleep 5
fi

# 7. Maximize window
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="