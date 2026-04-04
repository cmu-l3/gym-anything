#!/bin/bash
set -e
echo "=== Setting up Submit Proposal task ==="

source /workspace/scripts/task_utils.sh

# 1. Create the Proposal PDF with realistic content
# Using ImageMagick to create a simple PDF from text
mkdir -p /home/ga/Documents/Proposals
PROPOSAL_PATH="/home/ga/Documents/Proposals/Azure_Interior_Renovation_v2.pdf"

cat << EOF > /tmp/proposal_content.txt
PROPOSAL FOR AZURE INTERIOR
Date: $(date +%F)
Valid until: $(date -d "+30 days" +%F)

Scope of Work:
1. Open office layout redesign (3,000 sq ft)
2. Ergonomic furniture supply (50 workstations)
3. Acoustic paneling installation
4. Custom reception desk fabrication

Pricing Summary:
- Design Services: \$8,500
- Furniture & Fixtures: \$42,000
- Installation: \$5,500
- Total Estimated: \$56,000

Terms: 50% deposit, Net 30.
EOF

# Convert text to PDF
# Using convert (ImageMagick)
convert -page Letter -font Courier -pointsize 12 -size 612x792 \
    caption:"$(cat /tmp/proposal_content.txt)" \
    "$PROPOSAL_PATH" 2>/dev/null || {
    # Fallback if convert fails or font missing
    echo "Creating fallback PDF..."
    cat /tmp/proposal_content.txt > "${PROPOSAL_PATH%.pdf}.txt"
    # Create a dummy PDF just in case
    touch "$PROPOSAL_PATH"
}

chown -R ga:ga /home/ga/Documents/Proposals

# 2. Setup Odoo Data
wait_for_odoo

python3 - << 'PYEOF'
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find Partner "Azure Interior"
    partners = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', 'ilike', 'Azure Interior']]])
    if partners:
        partner_id = partners[0]
    else:
        partner_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [{
            'name': 'Azure Interior',
            'is_company': True,
            'email': 'info@azure-interior.com'
        }])

    # Find Stage "Qualified" (start stage) and "Proposition" (target stage)
    # We ensure "Qualified" exists to place the lead there
    stages = models.execute_kw(db, uid, password, 'crm.stage', 'search_read', 
        [[['name', '=', 'Qualified']]], {'fields': ['id'], 'limit': 1})
    start_stage_id = stages[0]['id'] if stages else 1

    # Check if opportunity already exists, if so reset it
    opp_name = 'Office Design Project - Azure Interior'
    existing = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', opp_name]]])
    
    lead_data = {
        'name': opp_name,
        'partner_id': partner_id,
        'expected_revenue': 56000,
        'stage_id': start_stage_id,
        'probability': 20,
        'type': 'opportunity',
        'description': 'Client requires full renovation of 2nd floor.',
        'tag_ids': [] # Clear tags
    }

    if existing:
        models.execute_kw(db, uid, password, 'crm.lead', 'write', [existing, lead_data])
        lead_id = existing[0]
        # Remove any existing attachments
        attachments = models.execute_kw(db, uid, password, 'ir.attachment', 'search',
            [[['res_model', '=', 'crm.lead'], ['res_id', '=', lead_id]]])
        if attachments:
            models.execute_kw(db, uid, password, 'ir.attachment', 'unlink', [attachments])
        print(f"Reset Lead ID: {lead_id}")
    else:
        lead_id = models.execute_kw(db, uid, password, 'crm.lead', 'create', [lead_data])
        print(f"Created Lead ID: {lead_id}")

    # Write lead ID to file for later use if needed
    with open('/tmp/task_lead_id.txt', 'w') as f:
        f.write(str(lead_id))

except Exception as e:
    print(f"Error setting up Odoo data: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# 3. Open Firefox and Login
# Navigate to CRM pipeline
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&cids=1&menu_id=139"

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="