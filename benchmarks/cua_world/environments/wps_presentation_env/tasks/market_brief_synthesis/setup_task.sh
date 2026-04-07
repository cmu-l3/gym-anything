#!/bin/bash
echo "=== Setting up market_brief_synthesis task ==="

source /workspace/scripts/task_utils.sh

kill_wps

pip3 install python-pptx lxml 2>/dev/null || true

rm -f /home/ga/Documents/EV_brief_corrected.pptx

date +%s > /tmp/market_brief_synthesis_start_ts

# Create the contaminated EV market brief
# Real data sources:
#   - US EV market share 2023: 7.6% of new vehicle sales (EIA, Apr 2024)
#   - US EV sales 2023: 1.19 million units (IEA Global EV Outlook 2024)
#   - US EV sales 2022: 0.88 million units (IEA)
#   - Tesla market share 2023: ~55% of US BEV market (Cox Automotive)
#   - Chevy Bolt EV base price 2024: $26,500 (GM, Jan 2024)
#   - BEV average transaction price Q1 2024: $53,633 (Kelley Blue Book, Apr 2024)
#   - IRA Section 30D clean vehicle tax credit: up to $7,500 (Pub.L. 117-169)
#   - Number of public EV chargers US: 169,015 (AFDC, Jan 2024)
#   - Consumer EV purchase intent 2024: 38% considering EV for next purchase (JD Power)
#   - LFP battery pack cost 2023: ~$126/kWh (BloombergNEF, Dec 2023)
#   - NMC battery pack cost 2023: ~$139/kWh (BloombergNEF)
#   - BYD global EV sales 2023: 3.02 million (BYD press release, Jan 2024)
# Pharmaceutical data (contaminating — not related to EV market):
#   - Drug wholesale market concentration: HHI reference placeholder data
python3 << 'PYEOF'
import os
from pptx import Presentation
from pptx.util import Inches, Pt, Emu

PPTX_PATH = '/home/ga/Documents/EV_market_brief.pptx'
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

# 20 slides total. Pharma contamination at positions 6, 13, 18 (1-indexed).
# EV slides are in the WRONG order (scrambled) — agent must reorder per spec.
# Correct EV order per spec:
#   1. Executive Summary
#   2. US EV Market Size and Growth
#   3. EV Adoption by Segment
#   4. Key OEM Market Share
#   5. Battery Technology Landscape
#   6. Charging Infrastructure Build-Out
#   7. Consumer Purchase Intent Drivers
#   8. Policy Environment: IRA and State Incentives
#   9. Competitive Threat: Chinese OEMs
#   10. 12-Month Outlook and Risks
# In the draft, EV slides appear in scrambled order (see below)
slides_data = [
    # Position 1: EV slide — correct spec position 3 (EV Adoption by Segment)
    ("EV Adoption by Segment",
     ["Battery Electric Vehicle (BEV) share of new sales 2023: 6.1% (IEA Global EV Outlook 2024)",
      "Plug-in Hybrid Electric Vehicle (PHEV) share 2023: 1.5%",
      "Combined BEV+PHEV share 2023: 7.6% (EIA, Apr 2024)",
      "Highest BEV adoption: California (25.4% of new sales), Washington (12.8%)",
      "SUV/CUV segment: 58% of BEV sales; sedan: 28%; pickup truck: 9%"]),

    # Position 2: EV slide — correct spec position 7 (Consumer Purchase Intent Drivers)
    ("Consumer Purchase Intent Drivers",
     ["38% of consumers considering EV as next vehicle purchase (JD Power 2024 EV Consideration Study)",
      "Top purchase barriers: range anxiety (52%), charging availability (47%), upfront cost (44%)",
      "Top purchase drivers: fuel savings (61%), environmental concern (48%), performance (39%)",
      "Average US EV owner saves ~$1,000/year in fuel vs. comparable ICE vehicle (DOE AFDC)",
      "BEV average range 2024: 291 miles (EPA); top model: Mercedes EQS 516 miles"]),

    # Position 3: EV slide — correct spec position 10 (12-Month Outlook and Risks)
    ("12-Month Outlook and Risks",
     ["Base case: US BEV market grows to 1.4M units in 2024 (IEA Stated Policies Scenario)",
      "Key risk: EV demand softening — Q1 2024 inventory days increased to 114 days vs. 54 for ICE (Cox)",
      "Key risk: Trade tensions with China could disrupt battery supply chains (critical minerals)",
      "Upside catalyst: Full IRA consumer incentive utilization as POS credit takes effect Jan 2024",
      "OEM risk: Ford EV division lost $4.7B in 2023 ($64,731 per unit sold) (Ford Q4 2023 earnings)"]),

    # Position 4: EV slide — correct spec position 9 (Competitive Threat: Chinese OEMs)
    ("Competitive Threat: Chinese OEMs",
     ["BYD 2023 global EV sales: 3.02 million units (surpassed Tesla globally in Q4 2023)",
      "BYD average selling price: ~$20,000 (vs. US BEV avg $53,633, KBB Q1 2024)",
      "Current US tariff on Chinese EVs: 25% + proposed 100% additional (USTR, May 2024)",
      "Chinese OEMs present in Canada, Mexico — potential USMCA arbitrage risk",
      "CATL battery market share: 37.4% global (SNE Research, 2023)"]),

    # Position 5: EV slide — correct spec position 1 (Executive Summary)
    ("Executive Summary",
     ["US EV market 2023: 1.19M units sold, +51% YoY (IEA Global EV Outlook 2024)",
      "Market share: 7.6% of new vehicle sales, up from 5.9% in 2022 (EIA)",
      "Tesla maintains leadership (~55% BEV share) but faces intensifying competition",
      "IRA incentives driving affordability; average transaction price declined 8% YoY",
      "Key risks: demand normalization, Chinese OEM competitive pressure, charging gaps"]),

    # Position 6 — PHARMA CONTAMINATION
    ("Global Pharma Distribution: Cold Chain Logistics Overview",
     ["Global pharmaceutical cold chain market: $21.3B in 2023 (IMARC Group)",
      "Cold chain segment growth: +8.2% CAGR 2023-2032",
      "Temperature-controlled drugs requiring cold chain: insulin, biologics, vaccines",
      "Primary failure mode: temperature excursion during last-mile delivery",
      "Regulatory: GDP guidelines (EMA 2013/C 343/01); WHO TRS 1025 (2022)"]),

    # Position 7: EV slide — correct spec position 4 (Key OEM Market Share)
    ("Key OEM Market Share",
     ["Tesla: ~55% of US BEV market 2023 (Cox Automotive Insights, Jan 2024)",
      "Chevrolet: 9.5% (Bolt EV/Bolt EUV); base price $26,500 (GM, Jan 2024)",
      "Ford: 7.4% (Mustang Mach-E, F-150 Lightning)",
      "Hyundai/Kia: 8.1% combined (Ioniq 5, Ioniq 6, EV6, EV9)",
      "BMW/Mercedes/Audi combined: 7.2%; Rivian 2.8%; VW 2.5%"]),

    # Position 8: EV slide — correct spec position 6 (Charging Infrastructure Build-Out)
    ("Charging Infrastructure Build-Out",
     ["US public EV chargers: 169,015 total (AFDC, January 2024)",
      "Level 2 chargers: 142,538 (84%); DC Fast Chargers: 26,477 (16%)",
      "NEVI Program: $5 billion for national EV charging network (IIJA, Nov 2021)",
      "Tesla Supercharger network opens to non-Tesla: 12,000+ chargers (Tesla Q3 2023)",
      "Charging gap: rural counties have 0.7 public chargers per 1,000 sq mi vs. urban 15.4"]),

    # Position 9: EV slide — correct spec position 8 (Policy Environment)
    ("Policy Environment: IRA and State Incentives",
     ["IRA Section 30D: up to $7,500 clean vehicle tax credit (Pub.L. 117-169, Aug 2022)",
      "As of Jan 2024: credit available at point of sale (POS) from dealerships",
      "Income limits: $150K single, $300K joint; vehicle MSRP cap: $55K car, $80K SUV/truck",
      "Critical minerals sourcing requirements: 50% of battery minerals must be US/FTA-sourced",
      "State supplements: CA $7,500 CVRP (income-qualified); NY $2,000; CO $5,000 (2024)"]),

    # Position 10: EV slide — correct spec position 2 (US EV Market Size and Growth)
    ("US EV Market Size and Growth",
     ["US BEV sales 2023: 1.19 million units (+51% YoY from 0.79M in 2022) (IEA 2024)",
      "US BEV sales 2022: 0.88 million units (combined BEV+PHEV) (IEA)",
      "Average transaction price BEV Q1 2024: $53,633 (vs. $65,000 in Q1 2023) (KBB, Apr 2024)",
      "Total addressable market 2023: 15.5M new vehicle registrations (Wards Auto)",
      "BEV market CAGR 2019-2023: 65% (IEA); projected 2024-2028 CAGR: 22% (BloombergNEF)"]),

    # Position 11: EV slide — correct spec position 5 (Battery Technology Landscape)
    ("Battery Technology Landscape",
     ["LFP (lithium iron phosphate) pack cost 2023: ~$126/kWh (BloombergNEF, Dec 2023)",
      "NMC (nickel manganese cobalt) pack cost 2023: ~$139/kWh (BloombergNEF)",
      "Tesla 4680 cell: 16% range improvement, 6x power vs 2170 cell (Tesla Battery Day 2020)",
      "Solid-state battery target: Toyota targets 2028 commercial production; QuantumScape 2025 pilot",
      "Battery price decline trajectory: $1,415/kWh (2010) → $139/kWh (2023) (BloombergNEF)"]),

    # Position 12: EV slide — carry-forward filler to reach position 12 before pharma slide 13
    ("Fleet Electrification: Commercial and Government Sector",
     ["US Postal Service: orders 66,000 NGDVs (9,250 battery-electric units) (USPS 2023)",
      "Amazon delivery fleet: 10,000 Rivian EDVs deployed by 2023 (Amazon Sustainability 2023)",
      "Government fleet: Executive Order 14008 targets 100% zero-emission federal fleet by 2035",
      "Total fleet BEV deployment 2023: ~78,000 units (Bloomberg Intelligence)",
      "Fleet total cost of ownership advantage: ~$0.03–0.07/mile vs. equivalent ICE fleet"]),

    # Position 13 — PHARMA CONTAMINATION
    ("Pharmaceutical Wholesaler Concentration (HHI Analysis)",
     ["Big Three wholesalers: McKesson, AmerisourceBergen (Cencora), Cardinal Health",
      "Combined revenue 2023: $770B; combined US drug wholesale market share: ~92%",
      "Herfindahl-Hirschman Index (HHI) for US drug wholesale: ~2,840 (highly concentrated)",
      "DOJ merger review threshold: HHI >2,500 = highly concentrated market",
      "Recent M&A: AmerisourceBergen rebranded Cencora (Aug 2023)"]),

    # Position 14: EV slide
    ("EV Supply Chain: Critical Minerals and Battery Materials",
     ["Lithium: US imports 100% of battery-grade lithium (USGS 2024); primary sources: Australia, Chile",
      "Cobalt: 70% of global supply from DRC (USGS); US dependency creates supply risk",
      "Nickel: Indonesia accounts for 42% of global mining (USGS 2024)",
      "IRA domestic sourcing requirements create battery supply chain onshoring pressure",
      "US lithium projects under development: Thacker Pass (NV), Salton Sea geothermal lithium"]),

    # Position 15: EV slide
    ("EV Dealership and Service Network Readiness",
     ["EV-certified dealers (US): 16,488 as of Q4 2023 (NADA Driving Forces Report)",
      "Average EV-specific service training hours: 40–80 hours per technician (OEM variance)",
      "Dealership charging infrastructure: 68% of franchised dealers have at least L2 charger installed",
      "Customer satisfaction with EV dealer experience: 795/1,000 vs. 845 for ICE (JD Power 2023)",
      "Tesla direct-sales model avoids franchise law constraints in 36 states"]),

    # Position 16: EV slide
    ("Used EV Market Dynamics",
     ["Used EV sales 2023: 340,000 units (up 32% YoY) (Cox Automotive 2024)",
      "Used BEV average transaction price: $31,844 (December 2023, Cox Automotive)",
      "Depreciation: 2-year-old BEV retains 47% MSRP vs. 53% for ICE (iSeeCars 2024)",
      "Used EV tax credit (IRA Sec 25E): up to $4,000 for qualified used EVs <$25,000",
      "Range anxiety resale impact: models with <200-mile EPA range depreciate 2x faster"]),

    # Position 17: EV slide
    ("Charging Economics: Utility Rate Design and Grid Impact",
     ["Average US residential electricity cost: 16.21 cents/kWh (EIA, Dec 2023)",
      "Average EV home charging cost per mile: ~$0.04–0.06 vs. gasoline ~$0.12–0.16/mile",
      "DCFC public charging commercial rate: $0.28–0.45/kWh or $0.20–0.35/min",
      "Grid load management: smart charging can shift 85% of residential demand off-peak (EPRI)",
      "Vehicle-to-grid (V2G): Ford F-150 Lightning supports 9.6 kW bidirectional export (V2H certified)"]),

    # Position 18 — PHARMA CONTAMINATION
    ("Specialty Drug Distribution Margins by Channel",
     ["Specialty pharmacy gross margin: 3–6% (vs. 1–2% for retail pharmacy) (Drug Channels Institute)",
      "Specialty drug share of US Rx spending 2023: 55% ($390B of $714B) (IQVIA)",
      "340B program hospitals: 50,000+ sites purchasing drugs at ~25–50% discount",
      "GPO (Group Purchasing Organization) contract penetration: ~98% of US hospitals",
      "Biosimilar uptake 2023: 29% market share (by volume) for adalimumab (AbbVie Humira)"]),

    # Position 19: EV slide
    ("OEM Profitability in EV Transition",
     ["Tesla automotive gross margin Q4 2023: 17.6% (down from 25.9% in Q4 2022) (Tesla 10-K 2023)",
      "Ford Pro ICE commercial vehicle margin: 12–14% vs. Ford EV (Model e): negative margin",
      "GM EV unit economics: on path to profitability by Q4 2025 (GM Investor Day 2023)",
      "VW ID.4 gross margin 2023: estimated <5% (Reuters, based on production cost estimates)",
      "Stellantis EV margin target: 10% EBIT by 2030 (Dare Forward 2030 plan)"]),

    # Position 20: EV slide
    ("EV Insurance and Total Cost of Ownership",
     ["BEV annual insurance cost 2023: avg $2,280 vs. $1,900 for ICE (Insurance.com)",
      "Premium driver: repair costs 26% higher due to battery and sensor complexity (CCC Intelligent Solutions)",
      "5-year TCO advantage: BEV ~$2,000–$8,000 cheaper than comparable ICE for high-mileage drivers",
      "Maintenance cost: BEV $0.061/mile vs. ICE $0.101/mile (DOE AFDC 2023)",
      "Roadside assistance: BEV flat tire rate 28% higher than ICE (Agero 2023 breakdown data)"]),
]

for title_text, body_lines in slides_data:
    add_slide(prs, title_text, body_lines)

prs.save(PPTX_PATH)
print(f"Created {PPTX_PATH} with {len(prs.slides)} slides")
PYEOF

# Create the EV brief specification document
cat > /home/ga/Desktop/ev_brief_spec.txt << 'DOCEOF'
VANTAGE MARKET RESEARCH CONSULTING
EV MARKET INTELLIGENCE BRIEF — CLIENT FORMAT SPECIFICATION
Document ID: VMR-EV-2024-Q1-SPEC
Date: March 8, 2024

This document specifies the required format and content order for the US Electric Vehicle
Market Intelligence Brief before it is delivered to the client (Meridian Capital Partners).

ISSUE 1: CROSS-REPORT CONTAMINATION

A quality review has identified that the assembled draft at /home/ga/Documents/EV_market_brief.pptx
contains slides from an unrelated pharmaceutical distribution research report. These slides
describe pharmaceutical supply chain, drug wholesale market concentration, and specialty
pharmacy margins — topics entirely unrelated to electric vehicles. They must be removed.
Any slide whose content describes pharmaceutical, drug, or medical distribution topics
rather than electric vehicles, batteries, charging infrastructure, or EV policy
must be deleted.

ISSUE 2: INCORRECT SLIDE ORDER

The remaining EV-topic slides must be reordered to match the following client-mandated
narrative structure. The client expects the brief to flow from market context →
competitive dynamics → enabling factors → risks:

REQUIRED SLIDE ORDER (after removing pharmaceutical slides):
  1.  Executive Summary
  2.  US EV Market Size and Growth
  3.  EV Adoption by Segment
  4.  Key OEM Market Share
  5.  Battery Technology Landscape
  6.  Charging Infrastructure Build-Out
  7.  Consumer Purchase Intent Drivers
  8.  Policy Environment: IRA and State Incentives
  9.  Competitive Threat: Chinese OEMs
  10. 12-Month Outlook and Risks

Slides not listed in the top-10 above (additional supporting content) should appear
AFTER slide 10 in the order they appear in the current draft (their relative order
among themselves does not need to change).

REQUIRED ACTION:
1. Remove all pharmaceutical distribution slides.
2. Reorder the first 10 EV slides to match the sequence above.
3. Save the corrected brief as: /home/ga/Documents/EV_brief_corrected.pptx
4. Do NOT modify the original file at: /home/ga/Documents/EV_market_brief.pptx
DOCEOF

chown ga:ga /home/ga/Documents/EV_market_brief.pptx
chown ga:ga /home/ga/Desktop/ev_brief_spec.txt
chown -R ga:ga /home/ga/Documents

launch_wps_with_file "/home/ga/Documents/EV_market_brief.pptx"

elapsed=0
while [ $elapsed -lt 60 ]; do
    dismiss_eula_if_present
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "EV_market_brief"; then
        echo "WPS loaded EV_market_brief.pptx after ${elapsed}s"
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
take_screenshot /tmp/market_brief_synthesis_start_screenshot.png

echo "=== market_brief_synthesis setup complete ==="
echo "EV_market_brief.pptx created and ready for review"
echo "Format specification placed on Desktop"
