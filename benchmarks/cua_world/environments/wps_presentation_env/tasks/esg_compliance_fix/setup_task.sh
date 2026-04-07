#!/bin/bash
echo "=== Setting up esg_compliance_fix task ==="

source /workspace/scripts/task_utils.sh

kill_wps

pip3 install python-pptx lxml 2>/dev/null || true

rm -f /home/ga/Documents/ESG_corrected.pptx

date +%s > /tmp/esg_compliance_fix_start_ts

# Create the ESG board presentation with injected errors
# Real data sources:
#   - GRI Standards (2021 Universal Standards):
#       GRI 302: Energy (302-1 energy within org, 302-2 energy outside org)
#       GRI 303: Water and Effluents (303-1 interactions, 303-3 water withdrawal)
#       GRI 305: Emissions (305-1 Scope 1, 305-2 Scope 2, 305-3 Scope 3)
#       GRI 401: Employment (401-1 new hires/turnover, 401-2 benefits, 401-3 parental leave)
#   - TCFD Recommendations (2017, updated 2021): 4 pillars in order:
#       1. Governance 2. Strategy 3. Risk Management 4. Metrics and Targets
#   - US manufacturing Scope 1 emission factors: EPA eGRID, EPA GHG inventory
#   - Science-based targets: SBTi Corporate Net-Zero Standard (Sep 2021)
# INJECTED ERRORS (agent must discover by reading memo):
#   - Slide 7:  "Emissions Disclosure (GRI 302-1)" — should be GRI 305-1 (Scope 1 emissions)
#   - Slide 10: "Energy Consumption Data (GRI 305-2)" — should be GRI 302-2 (energy outside org)
#   - Slide 15: "Water Withdrawal Data (GRI 401-3)" — should be GRI 303-3 (water withdrawal)
#   - TCFD slides in wrong order: positions 11,12,13,14 have Risk Mgmt, Governance, Targets, Strategy
#     Correct order: Governance(11), Strategy(12), Risk Mgmt(13), Metrics & Targets(14)
#   - Slides 19, 23: marketing/promotional slides that don't belong in ESG disclosure
python3 << 'PYEOF'
import os
from pptx import Presentation
from pptx.util import Emu

PPTX_PATH = '/home/ga/Documents/ESG_board_presentation.pptx'
os.makedirs('/home/ga/Documents', exist_ok=True)

prs = Presentation()
prs.slide_width  = Emu(9144000)
prs.slide_height = Emu(6858000)

def get_layout(prs):
    for layout in prs.slide_layouts:
        phs = {ph.placeholder_format.idx for ph in layout.placeholders}
        if 0 in phs and 1 in phs:
            return layout
    return prs.slide_layouts[1]

def add_slide(prs, title_text, body_lines):
    layout = get_layout(prs)
    slide = prs.slides.add_slide(layout)
    for ph in slide.placeholders:
        if ph.placeholder_format.idx == 0:
            ph.text = title_text
        elif ph.placeholder_format.idx == 1:
            tf = ph.text_frame
            tf.clear()
            for i, line in enumerate(body_lines):
                if i == 0:
                    tf.paragraphs[0].text = line
                else:
                    p = tf.add_paragraph()
                    p.text = line
    return slide

# 24 slides:
# - Slide 7:  WRONG GRI code (302-1 instead of 305-1)
# - Slide 10: WRONG GRI code (305-2 instead of 302-2)
# - Slide 11: TCFD Risk Management (should be position 3/Governance first)
# - Slide 12: TCFD Governance (should be position 1)
# - Slide 13: TCFD Metrics and Targets (should be position 4)
# - Slide 14: TCFD Strategy (should be position 2)
# - Slide 15: WRONG GRI code (401-3 instead of 303-3)
# - Slide 19: MARKETING SLIDE (must be removed)
# - Slide 23: MARKETING SLIDE (must be removed)

slides_data = [
    # Slide 1
    ("Harrington Industrial Group\nESG Disclosure Report FY2023",
     ["Board of Directors Presentation",
      "March 2024 | CONFIDENTIAL",
      "Prepared by: Head of Sustainability",
      "Reporting framework: GRI Standards 2021 | TCFD Recommendations 2021",
      "Third-party assurance: Bureau Veritas (limited assurance)"]),

    # Slide 2
    ("CEO Statement on Sustainability",
     ["FY2023 marks our third consecutive year of emissions reduction",
      "Scope 1 + Scope 2 emissions: 284,000 tCO2e (down 12% vs. FY2022)",
      "Science-Based Target approved: 42% absolute reduction by FY2030 (2018 base year)",
      "SBTi Corporate Net-Zero Standard alignment confirmed (Sep 2021 framework)",
      "Full ESG data assurance: Bureau Veritas limited assurance statement enclosed"]),

    # Slide 3
    ("ESG Performance Summary: FY2023 Highlights",
     ["Environment: Scope 1+2 emissions -12% YoY; renewable energy 41% of electricity",
      "Social: TRIR (Total Recordable Incident Rate) 0.84 (industry avg: 1.32, BLS 2023)",
      "Governance: Board ESG committee established Q1 2023; clawback policy updated",
      "Community: $2.3M in charitable contributions; 14,200 employee volunteer hours",
      "Data verified by Bureau Veritas (limited assurance, ISAE 3000)"]),

    # Slide 4
    ("Materiality Assessment: FY2023 Priority Topics",
     ["Process: double materiality assessment per ESRS and GRI methodology",
      "High financial materiality: climate transition risk, supply chain resilience",
      "High impact materiality: GHG emissions, workplace safety, water stewardship",
      "Stakeholder engagement: 48 interviews (investors 40%, NGOs 35%, suppliers 25%)",
      "Material topics mapped to GRI Standards 2021 Universal and Topical Standards"]),

    # Slide 5
    ("Environmental Overview: Climate Strategy",
     ["Net-zero target: Scope 1+2 by FY2040; Scope 3 by FY2050",
      "SBTi 1.5°C pathway: 42% Scope 1+2 reduction by FY2030 (approved Feb 2024)",
      "SBTi Scope 3: 25% absolute reduction by FY2030 (approved Feb 2024)",
      "Current renewable energy: 41% of total electricity (RECs + on-site solar)",
      "Internal carbon price: $65/tCO2e applied to capital investment decisions"]),

    # Slide 6
    ("GHG Inventory Boundary and Methodology",
     ["Organizational boundary: operational control approach (WBCSD/WRI GHG Protocol)",
      "Scope 1: direct emissions from owned/controlled sources (combustion, process)",
      "Scope 2: indirect emissions from purchased electricity (market-based)",
      "Scope 3 categories disclosed: Cat 1 (purchased goods), Cat 11 (use of sold products)",
      "Base year: FY2018; recalculation policy: >5% structural change triggers restatement"]),

    # Slide 7 — WRONG GRI CODE: should be GRI 305-1 (Scope 1 Emissions), not GRI 302-1
    ("Emissions Disclosure (GRI 302-1)",
     ["Scope 1 GHG emissions FY2023: 187,400 tCO2e (down 8% vs. FY2022: 203,600 tCO2e)",
      "Emissions by source: Natural gas combustion 61%, Diesel 28%, Refrigerants 11%",
      "Emission factors: EPA eGRID 2022 and EPA GHG Emission Factors Hub (Apr 2023)",
      "Biogenic CO2 from biomass combustion: 2,100 tCO2 (reported separately, GHG Protocol)",
      "GRI 305-1 disclosure | Assurance: Bureau Veritas limited assurance"]),

    # Slide 8
    ("Scope 2 Emissions and Renewable Energy (GRI 305-2)",
     ["Scope 2 (market-based) FY2023: 96,600 tCO2e (down 19% vs. FY2022: 119,300 tCO2e)",
      "Renewable electricity: 41% (RECs from wind: 28%; on-site solar: 13%)",
      "Scope 2 location-based: 128,400 tCO2e (eGRID US average grid factors)",
      "Renewable Energy Certificates (RECs): Green-e certified, 2023 vintage",
      "GRI 305-2 disclosure | Assurance: Bureau Veritas limited assurance"]),

    # Slide 9
    ("Scope 3 Emissions (GRI 305-3)",
     ["Total Scope 3: 1.84 million tCO2e (Cats 1 and 11 only; others not yet quantified)",
      "Category 1 (purchased goods and services): 1.12M tCO2e (EEIO method, EPA USEEIO v2)",
      "Category 11 (use of sold products): 0.72M tCO2e (product lifecycle assessment)",
      "Significant omissions: Cat 3 (fuel/energy), Cat 6 (business travel) — estimated immaterial",
      "GRI 305-3 disclosure | Not externally assured (calculation in progress)"]),

    # Slide 10 — WRONG GRI CODE: should be GRI 302-2 (Energy outside organization), not GRI 305-2
    ("Energy Consumption Data (GRI 305-2)",
     ["Total energy consumption within organization FY2023: 4.82 million GJ",
      "  - Natural gas: 2.91 million GJ (60%)",
      "  - Electricity purchased: 1.54 million GJ (32%)",
      "  - Diesel and other liquid fuels: 0.37 million GJ (8%)",
      "Energy intensity: 14.3 GJ per tonne of product (down 6% YoY)",
      "GRI 302-1 disclosure | Assurance: Bureau Veritas limited assurance"]),

    # Slide 11 — TCFD WRONG POSITION: Risk Management (should be position 3, here at position 1)
    ("TCFD Pillar 3: Risk Management",
     ["Climate risk identification process integrated into enterprise risk register (ERM)",
      "Physical risks assessed: acute (flood, wildfire) and chronic (temperature, drought)",
      "Transition risks: carbon pricing, policy/regulatory, technology, market/reputational",
      "Scenario analysis conducted: IEA NZE 2050 (1.5°C), IPCC RCP 4.5 (2°C), RCP 8.5 (3°C)",
      "Climate risk owners assigned at facility level; quarterly ERM committee review"]),

    # Slide 12 — TCFD WRONG POSITION: Governance (should be position 1, here at position 2)
    ("TCFD Pillar 1: Governance",
     ["Board ESG Committee: established Q1 2023; 3 independent directors",
      "Board oversight: quarterly ESG performance review; annual climate risk briefing",
      "Management: Head of Sustainability reports to CEO; climate risk in exec compensation",
      "ESG metrics linked to 15% of annual short-term incentive for CEO and CFO",
      "Clawback policy updated Q2 2023 to include ESG metric restatements"]),

    # Slide 13 — TCFD WRONG POSITION: Metrics & Targets (should be position 4, here at position 3)
    ("TCFD Pillar 4: Metrics and Targets",
     ["GHG emissions (Scope 1+2): 284,000 tCO2e FY2023; target 42% reduction by FY2030",
      "Energy intensity: 14.3 GJ/tonne product; target 20% reduction by FY2028",
      "Renewable electricity: 41%; target 80% by FY2030",
      "TRIR: 0.84; target <0.70 by FY2025 (safety as climate-adjacent physical risk proxy)",
      "Internal carbon price: $65/tCO2e; reviewed annually; target $100/tCO2e by FY2027"]),

    # Slide 14 — TCFD WRONG POSITION: Strategy (should be position 2, here at position 4)
    ("TCFD Pillar 2: Strategy",
     ["Climate scenarios inform strategic planning horizon: 2030 (near) and 2050 (long)",
      "1.5°C scenario (IEA NZE 2050): accelerated capex for electrification; carbon cost $250+/t by 2050",
      "2°C scenario (IPCC RCP 4.5): moderate transition costs; moderate physical risk",
      "3°C scenario (IPCC RCP 8.5): material flood risk at 3 manufacturing sites",
      "Strategy: prioritize renewable energy, heat pumps, and carbon capture feasibility study"]),

    # Slide 15 — WRONG GRI CODE: should be GRI 303-3 (Water Withdrawal), not GRI 401-3
    ("Water Withdrawal Data (GRI 401-3)",
     ["Total water withdrawal FY2023: 3.84 million cubic meters",
      "  - Surface water: 2.31M m³ (60%)",
      "  - Groundwater: 1.22M m³ (32%)",
      "  - Municipal/third-party water: 0.31M m³ (8%)",
      "Water intensity: 11.4 m³ per tonne of product (down 4% YoY)",
      "GRI 303-3 disclosure | Assurance: Bureau Veritas limited assurance"]),

    # Slide 16
    ("Water Stewardship: Risk and Reduction Program (GRI 303-1)",
     ["Water-stressed sites: 3 of 14 facilities in high/very high water-stressed areas (WRI Aqueduct)",
      "Reduction target: 15% absolute water withdrawal reduction by FY2028 (vs. FY2022 base)",
      "Progress: installed closed-loop cooling at 2 sites; saved 180,000 m³/year",
      "Wastewater treatment: 98% of process wastewater treated before discharge",
      "GRI 303-1 disclosure"]),

    # Slide 17
    ("Social: Workforce Safety and Health (GRI 403)",
     ["TRIR FY2023: 0.84 per 200,000 hours worked (BLS manufacturing avg: 1.32, 2023)",
      "Lost-time incident rate: 0.31 (BLS manufacturing avg: 0.57, 2023)",
      "Fatalities: 0 (FY2023 and FY2022)",
      "Near-miss reporting rate: 12.4 per 200,000 hours (programs incentivize near-miss reporting)",
      "GRI 403-9 (Work-related injuries) disclosure | Assured: Bureau Veritas"]),

    # Slide 18
    ("Social: Employment, Diversity, and Human Rights (GRI 401, 405)",
     ["Total employees FY2023: 14,847 (FY2022: 14,213, +4.5%)",
      "New hires FY2023: 2,184 (15% of workforce) (GRI 401-1)",
      "Employee turnover FY2023: 11.3% (manufacturing sector avg: 13.2%, BLS 2023)",
      "Gender diversity: 34% women in workforce; 28% in senior management",
      "GRI 405-1 diversity disclosure | GRI 409 forced labor: no incidents reported FY2023"]),

    # Slide 19 — MARKETING SLIDE (must be removed from ESG disclosure)
    ("Harrington: A Great Place to Work — Employee Testimonials",
     ["\"Working at Harrington has transformed my career\" — Plant Supervisor, Roanoke",
      "\"The sustainability initiatives make me proud to work here\" — Process Engineer",
      "\"Best safety culture I've experienced in 20 years\" — Maintenance Lead",
      "Harrington has been named to Forbes Best Employers list 3 years running",
      "Note: This slide is from the recruiting deck and does not belong in the ESG disclosure"]),

    # Slide 20
    ("Supply Chain: Responsible Sourcing (GRI 308, 414)",
     ["Tier 1 supplier ESG assessment coverage: 78% by spend (2023 target: 75%) — exceeded",
      "Suppliers with Ecovadis assessment: 142 (covering 68% of strategic spend)",
      "High-risk suppliers (below 45/100 score): 23 identified; corrective action plans in place",
      "Conflict minerals reporting: compliant with Dodd-Frank Section 1502 (3TG sourcing)",
      "GRI 308-1 and GRI 414-1 disclosure"]),

    # Slide 21
    ("Governance: Board Composition and ESG Oversight (GRI 2-9)",
     ["Board size: 11 directors; 9 independent (82%)",
      "Board gender diversity: 45% women (5 of 11 directors)",
      "Board diversity: 36% from underrepresented racial/ethnic groups",
      "ESG expertise: 3 directors with sustainability or environmental qualifications",
      "GRI 2-9 disclosure | Say-on-pay approval 2023: 91.4%"]),

    # Slide 22
    ("Governance: Executive Compensation and ESG Metrics",
     ["Short-term incentive: 15% weighted to ESG KPIs (CEO and CFO)",
      "ESG KPIs in compensation: TRIR target, Scope 1+2 reduction %, diversity hiring %",
      "Long-term incentive: performance share units (PSUs) include 20% ESG modifier",
      "Compensation committee ESG oversight: quarterly ESG KPI review",
      "GRI 2-19 and GRI 2-20 disclosure"]),

    # Slide 23 — MARKETING SLIDE (must be removed from ESG disclosure)
    ("Harrington Industrial Group — Why Invest In Us",
     ["Strong ESG ratings: MSCI AA, Sustainalytics Low Risk 14.3",
      "Dividend growth: 8% CAGR over 5 years",
      "Revenue CAGR FY2019-2023: 11.4% (from $4.2B to $6.8B)",
      "Strong free cash flow: $840M FCF in FY2023 (12.4% FCF margin)",
      "Note: This slide belongs to the Investor Relations deck, not the ESG disclosure report"]),

    # Slide 24
    ("GRI Content Index and Assurance Statement",
     ["Full GRI Content Index available at harrington-esg.com/2023-report",
      "Assurance level: Limited assurance (ISAE 3000 Revised, direct engagements)",
      "Assurance provider: Bureau Veritas Certification (accredited)",
      "Material topics assured: GRI 305 (Emissions), GRI 302 (Energy), GRI 403 (Safety)",
      "Assurance statement available at harrington-esg.com/assurance-2023"]),
]

for title_text, body_lines in slides_data:
    add_slide(prs, title_text, body_lines)

prs.save(PPTX_PATH)
print(f"Created {PPTX_PATH} with {len(prs.slides)} slides")
PYEOF

# Create the auditor memo (describes issues without naming slide positions)
cat > /home/ga/Desktop/esg_auditor_memo.txt << 'DOCEOF'
HARRINGTON INDUSTRIAL GROUP
ESG DISCLOSURE REPORT — AUDITOR REVIEW MEMO

From: Bureau Veritas ESG Assurance Team
To: Head of Sustainability, Harrington Industrial Group
Date: March 8, 2024
Re: Pre-Distribution Review — ESG Board Presentation

Prior to board distribution and publication, we have identified three categories of
errors in the draft at /home/ga/Documents/ESG_board_presentation.pptx.
All issues must be corrected before the report is finalized.

─────────────────────────────────────────────────────────────────
ISSUE 1: INCORRECT GRI STANDARD CODES IN SLIDE TITLES
─────────────────────────────────────────────────────────────────
Three slides have incorrect GRI Standard codes in their titles. The GRI Standards
are precise and cannot be mixed up — an incorrect code could be flagged as
misrepresentation by investors or regulators.

Reference — correct GRI code assignments:
  • GRI 302: Energy — covers energy consumption within and outside the organization
      302-1: Energy consumption within the organization
      302-2: Energy consumption outside of the organization
  • GRI 303: Water and Effluents — covers water use and effluents
      303-3: Water withdrawal
  • GRI 305: Emissions — covers greenhouse gas emissions
      305-1: Direct (Scope 1) GHG emissions
      305-2: Energy indirect (Scope 2) GHG emissions
      305-3: Other indirect (Scope 3) GHG emissions
  • GRI 401: Employment — covers employment and workforce practices
      401-3: Parental leave

Review all slides whose titles contain GRI Standard codes. Compare the code in the
title against the actual content of the slide body. Wherever the code does not match
the content, correct the title to use the accurate GRI code.

─────────────────────────────────────────────────────────────────
ISSUE 2: TCFD SECTION IN WRONG SEQUENCE
─────────────────────────────────────────────────────────────────
The TCFD (Task Force on Climate-related Financial Disclosures) framework specifies a
precise order for the four disclosure pillars. The current draft has these pillars out
of sequence.

The correct required order is:
  1. TCFD Pillar 1: Governance
  2. TCFD Pillar 2: Strategy
  3. TCFD Pillar 3: Risk Management
  4. TCFD Pillar 4: Metrics and Targets

Find the four TCFD pillar slides in the deck and reorder them so they appear in the
sequence above (Governance → Strategy → Risk Management → Metrics and Targets).
Their position relative to other non-TCFD slides does not need to change — only their
order relative to each other must be corrected.

─────────────────────────────────────────────────────────────────
ISSUE 3: NON-DISCLOSURE MARKETING CONTENT IN REPORT
─────────────────────────────────────────────────────────────────
An ESG Disclosure Report is a regulatory and stakeholder-facing document and must not
contain recruiting marketing content or investor relations promotional material.
We have identified at least two slides that appear to have been copied from other
internal decks (employee recruiting or IR presentation). These slides contain
employee testimonials and investment highlights — content that is categorically
inappropriate for an ESG disclosure document.

Identify and delete any slides that contain promotional or marketing content that
is not part of ESG disclosures, metrics, methodology, or governance.

─────────────────────────────────────────────────────────────────
REQUIRED ACTION
─────────────────────────────────────────────────────────────────
Correct all three issues above. Save the corrected presentation as:

    /home/ga/Documents/ESG_corrected.pptx

Do NOT modify the original file at: /home/ga/Documents/ESG_board_presentation.pptx
DOCEOF

chown ga:ga /home/ga/Documents/ESG_board_presentation.pptx
chown ga:ga /home/ga/Desktop/esg_auditor_memo.txt
chown -R ga:ga /home/ga/Documents

launch_wps_with_file "/home/ga/Documents/ESG_board_presentation.pptx"

elapsed=0
while [ $elapsed -lt 60 ]; do
    dismiss_eula_if_present
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "ESG_board_presentation"; then
        echo "WPS loaded ESG_board_presentation.pptx after ${elapsed}s"
        sleep 3
        break
    fi
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "WPS Office"; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1280 630 click 1 2>/dev/null || true
        sleep 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

maximize_wps
sleep 2
take_screenshot /tmp/esg_compliance_fix_start_screenshot.png

echo "=== esg_compliance_fix setup complete ==="
echo "ESG_board_presentation.pptx created (24 slides)"
echo "Presentation requires review per auditor memo"
echo "Auditor memo placed on Desktop"
