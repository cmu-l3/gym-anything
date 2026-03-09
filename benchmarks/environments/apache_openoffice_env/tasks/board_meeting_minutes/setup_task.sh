#!/bin/bash
set -e
echo "=== Setting up board_meeting_minutes task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Document directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous run artifacts
rm -f /home/ga/Documents/RCHD_Board_Minutes_2024-11-14.odt
rm -f /home/ga/Documents/raw_meeting_notes.txt

# Create the raw meeting notes file
cat > /home/ga/Documents/raw_meeting_notes.txt << 'NOTESEOF'
RCHD Board of Directors Mtg - Nov 14 2024
Admin Conference Room, 1400 W Central Park Ave, Davenport IA 52804
Called for 6:30pm - actually started 6:32 (waiting on quorum)

Present: Pat Hollingsworth (chair), Dr. Marcus Chen (vice chair), Theresa Okafor (sec/treas), Jim Fredricksen, Linda Zhao-Espinoza, Robert Achebe
Absent: Colleen Brannigan - called in, flu
Staff attending: Sam Dietrich CEO, Angela Rasmussen CFO, Dr. Yuki Tanaka CNO, Derek Montoya VP Facilities
Also present: 2 members of public (signed in as Karen Weiss and Tom Prudhomme)
Recording secretary: Janet Kowalski, Exec Asst

6:32pm - Pat called meeting to order. Confirmed quorum - 6 of 7 directors present. Read mission statement.

APPROVAL OF PREV MINUTES
Theresa moved to approve minutes from Oct 10 2024 regular meeting as distributed. Jim seconded.
Discussion: none
Vote: all in favor, none opposed, none abstaining. APPROVED unanimously (6-0).

FINANCIAL REPORT - Angela R presented
Q3 FY2024 (Jul-Sep):
- Total revenue $47.2M (2.1% above budget)
- Total expenses $44.8M (0.8% under budget)  
- Operating surplus $2.4M
- Cash on hand 62 days (target >45)
- Bad debt provision $1.9M (trending down from $2.3M in Q2)
- Medicare mix 41%, Medicaid 18%, commercial 34%, self-pay 7%
Angela noted volumes up across most service lines, especially ortho and cardiac cath. ED visits averaged 142/day vs 131 budget.
Dr. Chen asked about supply chain costs - Angela said pharmacy costs up 6% but offset by GPO renegotiation saving $340K.
Jim asked about capital budget burn rate - Angela said 67% committed YTD on $12.8M capital plan.
No motion needed - informational only.

OLD BUSINESS

1) MRI Replacement Project
Derek Montoya reported. $3.2M Siemens MAGNETOM Sola 1.5T approved at June meeting. Construction of new MRI suite on track. Demolition of old suite complete. Electrical and HVAC rough-in 80% done. Siemens confirmed delivery week of Jan 13 2025. Installation/calibration est 6-8 weeks. Go-live target March 2025.
Pat asked about contingency budget - Derek said $180K contingency, $42K spent so far on unexpected asbestos abatement in ceiling plenum.
Dr. Chen asked about staff training - Dr. Tanaka said 4 MRI techs enrolled in Siemens applications training in Milwaukee, Jan 6-10.
No motion needed - status update.

2) HVAC Renovation Phase 2
Derek presented. Phase 2 covers 3rd floor patient rooms and surgical suite air handlers. Received 3 bids:
  - Quad Cities Mechanical: $890,000 (recommended)
  - Hawkeye Climate Systems: $1,020,000
  - River Bend Environmental: $947,000
Derek recommended QCM based on lowest compliant bid + prior satisfactory work on Phase 1.
Discussion: Jim asked about timeline - Derek said 14 weeks, starting Dec 2, mostly off-hours work to minimize disruption. Linda asked about infection control during construction - Dr. Tanaka confirmed ICRA Class III protocols in place.
Robert moved to approve contract with Quad Cities Mechanical for $890,000 for HVAC Phase 2. Linda seconded.
Vote: 6-0 in favor. APPROVED.
ACTION: Sam to execute contract by Nov 29.

3) Nurse Staffing Initiative Update
Dr. Tanaka reported. Goal was 20 new RN hires by end of CY2024. Status: 12 offers extended, 8 started, 4 in onboarding/credentialing pipeline. Biggest wins in med-surg (4) and ICU (2). Still struggling with OR staffing - 2 positions open 6+ months.
Travel nurse FTEs down from 18 in Q1 to 11 current. Cost savings: travel nurse spend down 34% ($1.2M reduction annualized).
Theresa asked about retention - Dr. Tanaka said 1-year retention rate for new hires is 84%, up from 76% last year. Attributed to mentorship program and sign-on bonus structure.
No motion needed.
ACTION: Dr. Tanaka to provide travel nurse cost trend report for Jan meeting.

NEW BUSINESS

1) FY2025 Operating Budget
Angela presented proposed FY2025 operating budget: $198.4M total. Revenue assumptions: 3.2% volume growth, 2.8% rate increases (weighted avg across payers). Expense assumptions: 4.1% labor cost increase (includes union contract step increases), 3.5% supply inflation, 2.0% other.
Projected operating margin 2.1% ($4.2M surplus). Capital budget request $14.1M (includes $5.8M for new cath lab, $2.1M IT infrastructure, remainder maintenance capital).
Discussion was lengthy - about 35 min.
Jim expressed concern that capital allocation was still below peer benchmark (Riverbend 7.1% of revenue vs peer avg 8.4%). Wants more aggressive investment. Pat noted board's fiduciary obligation for sustainability.
Linda asked about union contract renewal risk - Angela said current CBA expires Jun 2025, budgeted 4.5% increase as worst-case.
Dr. Chen moved to approve FY2025 operating budget as presented ($198.4M). Theresa seconded.
Roll call vote:
  Hollingsworth - aye
  Chen - aye
  Okafor - aye
  Fredricksen - NAY (wants higher capital allocation)
  Zhao-Espinoza - aye
  Achebe - aye
APPROVED 5-1.
ACTION: Angela to distribute departmental budget breakdowns to board by Dec 13.

2) Community Health Needs Assessment (CHNA)
Sam presented. Federal requirement for tax-exempt hospitals - must complete CHNA every 3 years. Last one was 2022. Need to initiate 2025 cycle. Proposes partnering with UnityPoint Health - Trinity (Bettendorf) for joint Quad Cities CHNA. Cost share: $145K RCHD portion (UnityPoint covering $160K). Vendor: Conduent Healthy Communities.
Benefits of joint approach: shared survey costs, larger sample size, more comprehensive community picture, aligns with state health dept preference.
Timeline: kickoff Jan 2025, community surveys Feb-Apr, focus groups May, draft report Aug, final Sept 2025.
Linda moved to authorize CEO to enter into CHNA partnership agreement with UnityPoint Health for joint CHNA, RCHD share not to exceed $145,000. Robert seconded.
Vote: 6-0 APPROVED.
ACTION: Sam to finalize CHNA contract with UnityPoint by Dec 20.

3) Board Officer Elections
Annual election per bylaws Article IV. Pat turned chair over to Sam (CEO serves as temporary presiding officer per bylaws).
Jim nominated existing slate: Patricia Hollingsworth Chair, Dr. Marcus Chen Vice Chair, Theresa Okafor Secretary/Treasurer.
No additional nominations. Jim moved to re-elect slate by acclamation. Dr. Chen seconded.
Vote: 6-0 APPROVED. Pat resumed chair.

QUALITY & PATIENT SAFETY REPORT
Dr. Tanaka presented quarterly quality dashboard:
- CMS Star Rating: 4 out of 5 (maintained)
- HCAHPS Overall Rating: 78th percentile (up from 71st in Q2)
- 30-day all-cause readmission rate: 11.2% (target <12%)
- Hospital-acquired infection rate: 0.7 per 1000 patient-days (down from 0.9)
- Falls with injury: 2 (both minor, on med-surg)
- Serious safety events: 0
- Surgical site infection: 1 case (knee replacement, resolved with antibiotics)
Dr. Chen commended nursing staff on HCAHPS improvement. Pat asked about patient experience initiatives - Dr. Tanaka cited hourly rounding compliance now at 91%.
ACTION: Dr. Tanaka to post updated quality dashboard to board portal by Nov 22.

PUBLIC COMMENT
Karen Weiss (lives on W 14th St) - asked about timeline for parking expansion. Complained about staff parking overflow onto residential streets. Pat acknowledged concern, said it's being studied.
ACTION: Derek to schedule community forum on parking expansion plans, before Jan board mtg.

Tom Prudhomme - thanked hospital for new pediatric wing. His grandson received excellent care there last month. Board expressed appreciation.

OTHER/ANNOUNCEMENTS
Pat reminded board of holiday employee recognition event Dec 18, 5pm, cafeteria. All board members invited.
Next regular meeting: Thursday January 9, 2025, 6:30 PM, Admin Conference Room.
ACTION: Pat to circulate draft Jan 9 agenda by Dec 27.

ADJOURNMENT
Theresa moved to adjourn. Robert seconded. All in favor.
Meeting adjourned at 9:18 PM.

Respectfully submitted,
Janet Kowalski, Recording Secretary
(draft - pending board review and approval)
NOTESEOF

chown ga:ga /home/ga/Documents/raw_meeting_notes.txt
chmod 644 /home/ga/Documents/raw_meeting_notes.txt

# Start OpenOffice Writer with a blank document
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    sleep 8
fi

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice"; then
        echo "OpenOffice window found"
        DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Dismiss any startup dialogs (like "Welcome")
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="