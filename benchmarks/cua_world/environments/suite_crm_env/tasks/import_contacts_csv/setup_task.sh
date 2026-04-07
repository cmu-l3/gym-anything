#!/bin/bash
set -e
echo "=== Setting up Import Contacts CSV task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Record initial contact count
INITIAL_COUNT=$(suitecrm_count "contacts" "deleted=0")
echo "$INITIAL_COUNT" > /tmp/initial_contact_count.txt
echo "Initial contact count: $INITIAL_COUNT"

# ---------------------------------------------------------------
# Create the CSV file with realistic trade show lead data
# ---------------------------------------------------------------
echo "--- Creating CSV file ---"
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/tradeshow_leads.csv << 'CSVEOF'
First Name,Last Name,Job Title,Company,Email,Office Phone,Mobile Phone,Street Address,City,State,Zip Code,Country,Notes
Marcus,Chen,Procurement Director,Pacific Rim Trading Co.,m.chen@pacrimtrading.com,(415) 882-2847,(415) 390-9312,2200 Embarcadero Rd,San Francisco,CA,94107,USA,Met at NAWGA 2024 booth 417 - interested in bulk organic pricing
Diana,Vasquez,VP of Supply Chain,Heartland Food Distributors,dvasquez@heartlandfood.com,(816) 471-3390,(816) 555-7721,400 E 9th St,Kansas City,MO,64106,USA,Discussed regional distribution partnership for Midwest corridor
Robert,Okafor,Purchasing Manager,Great Lakes Wholesale Inc.,rokafor@greatlakeswholesale.com,(312) 628-4450,(773) 555-1188,233 S Wacker Dr,Chicago,IL,60606,USA,Currently sourcing new frozen food suppliers - follow up Q1
Sarah,Johansson,Director of Operations,Nordic Fresh Supply,s.johansson@nordicfresh.com,(612) 339-8820,(651) 555-4403,80 S 8th St,Minneapolis,MN,55402,USA,Interested in cold chain logistics collaboration
James,Whitfield,Chief Buyer,Southern States Distribution,jwhitfield@southernstatesdist.com,(404) 521-6700,(770) 555-3319,191 Peachtree St NE,Atlanta,GA,30303,USA,Large volume buyer - wants quarterly pricing review meetings
Priya,Ramanathan,Supply Chain Analyst,Metro Food Services,pramanathan@metrofoodsvcs.com,(212) 736-5500,(917) 555-8847,11 Times Square,New York,NY,10036,USA,Data-driven procurement approach - send product catalog with margins
Thomas,Brennan,Warehouse Operations Manager,Atlantic Coast Wholesale,tbrennan@atlanticcoastwh.com,(617) 338-2200,(508) 555-6654,100 Summer St,Boston,MA,02110,USA,Expanding warehouse capacity - interested in new product lines
Lisa,Nakamura,Category Manager,Evergreen Distribution Partners,lnakamura@evergreendist.com,(206) 624-7100,(425) 555-2290,1201 3rd Ave,Seattle,WA,98101,USA,Specialty Asian foods category - high growth potential
David,Kowalski,Procurement Specialist,Midwest Provisions LLC,dkowalski@midwestprovisions.com,(414) 271-8800,(262) 555-7735,770 N Water St,Milwaukee,WI,53202,USA,Small but growing operation - budget-conscious buyer
Angela,Torres,Director of Purchasing,Gulf Coast Trading Group,atorres@gulfcoasttrading.com,(713) 650-3300,(281) 555-4412,1000 Louisiana St,Houston,TX,77002,USA,Multi-state operation TX/LA/MS - high volume potential
Michael,Ostrowski,Logistics Coordinator,Summit Wholesale Foods,mostrowski@summitwholesale.com,(303) 572-4200,(720) 555-9981,1625 Broadway,Denver,CO,80202,USA,Looking to optimize delivery routes - interested in regional hub model
Karen,Blackwood,VP of Procurement,Cascade Supply Network,kblackwood@cascadesupply.com,(503) 228-6100,(971) 555-3367,1120 NW Couch St,Portland,OR,97209,USA,Sustainable sourcing focus - wants organic and fair-trade options
CSVEOF

chown ga:ga /home/ga/Documents/tradeshow_leads.csv
echo "CSV file created at /home/ga/Documents/tradeshow_leads.csv"

# ---------------------------------------------------------------
# Ensure none of these contacts already exist (clean state)
# ---------------------------------------------------------------
echo "--- Cleaning pre-existing test contacts ---"
CONTACT_NAMES=(
    "Marcus:Chen"
    "Diana:Vasquez"
    "Robert:Okafor"
    "Sarah:Johansson"
    "James:Whitfield"
    "Priya:Ramanathan"
    "Thomas:Brennan"
    "Lisa:Nakamura"
    "David:Kowalski"
    "Angela:Torres"
    "Michael:Ostrowski"
    "Karen:Blackwood"
)

for name_pair in "${CONTACT_NAMES[@]}"; do
    first="${name_pair%%:*}"
    last="${name_pair##*:}"
    suitecrm_db_query "UPDATE contacts SET deleted=1 WHERE first_name='${first}' AND last_name='${last}' AND deleted=0" 2>/dev/null || true
done

# ---------------------------------------------------------------
# Ensure Firefox is running and logged into SuiteCRM
# ---------------------------------------------------------------
echo "--- Ensuring SuiteCRM is accessible ---"
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Contacts&action=index"

sleep 3

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png
echo "Initial state screenshot saved"

echo "=== Task setup complete ==="