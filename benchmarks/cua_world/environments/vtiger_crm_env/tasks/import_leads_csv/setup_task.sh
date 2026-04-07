#!/bin/bash
echo "=== Setting up import_leads_csv task ==="

source /workspace/scripts/task_utils.sh

# 1. Create the realistic CSV file for the agent to import
mkdir -p /home/ga/Documents
cat << 'EOF' > /home/ga/Documents/tradeshow_leads.csv
First Name,Last Name,Company,Email,Phone,City,State,Lead Source,Description
Rachel,Dominguez,Greenfield Landscaping LLC,r.dominguez@greenfieldland.com,512-555-0147,Austin,TX,Trade Show,Interested in commercial lawn care scheduling software
Marcus,Oyelaran,BrightPath Solar Inc,moyelaran@brightpathsolar.com,720-555-0283,Denver,CO,Trade Show,Asked about lead tracking for residential solar installs
Theresa,Kowalski,Apex Property Management,tkowalski@apexpm.net,312-555-0391,Chicago,IL,Trade Show,Needs tenant communication and maintenance ticket system
David,Nwosu,Harbor Freight Logistics,dnwosu@harborfl.com,904-555-0422,Jacksonville,FL,Trade Show,Looking for shipment tracking and customer notification CRM
Priya,Chakraborty,Sunrise Home Health Services,pchakraborty@sunrisehhs.org,615-555-0518,Nashville,TN,Trade Show,Wants patient follow-up scheduling and caregiver assignment
James,Whitfield,Summit Roofing Contractors,jwhitfield@summitroofing.com,602-555-0634,Phoenix,AZ,Trade Show,Interested in estimate tracking and job scheduling features
Linda,Ferreira,Coastal Realty Group,lferreira@coastalrealtygrp.com,843-555-0759,Charleston,SC,Trade Show,Asked about open house lead capture and drip email campaigns
Omar,Al-Rashidi,Pinnacle IT Solutions,oalrashidi@pinnacleit.io,503-555-0861,Portland,OR,Trade Show,Evaluating CRM for managed services client relationship mgmt
EOF
chmod 666 /home/ga/Documents/tradeshow_leads.csv

# 2. Record Task Start Time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Clean up any existing matching leads to ensure a perfectly clean state
for lname in Dominguez Oyelaran Kowalski Nwosu Chakraborty Whitfield Ferreira Al-Rashidi; do
    CRMID=$(vtiger_db_query "SELECT leadid FROM vtiger_leaddetails WHERE lastname='$lname' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$CRMID" ]; then
        echo "Cleaning up pre-existing lead: $lname"
        vtiger_db_query "UPDATE vtiger_crmentity SET deleted=1 WHERE crmid=$CRMID"
    fi
done

# 4. Record Initial Count of undeleted leads
INITIAL_LEAD_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_leaddetails l INNER JOIN vtiger_crmentity e ON l.leadid = e.crmid WHERE e.deleted = 0" | tr -d '[:space:]')
echo "$INITIAL_LEAD_COUNT" > /tmp/initial_lead_count.txt
echo "Initial lead count: $INITIAL_LEAD_COUNT"

# 5. Ensure logged in and navigate to Leads list view
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Leads&view=List"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/import_leads_initial.png

echo "=== import_leads_csv task setup complete ==="