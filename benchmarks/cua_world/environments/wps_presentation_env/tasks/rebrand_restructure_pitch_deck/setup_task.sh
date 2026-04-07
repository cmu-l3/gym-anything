#!/bin/bash
echo "=== Setting up rebrand_restructure_pitch_deck task ==="

source /workspace/scripts/task_utils.sh

# Kill any running WPS instance
kill_wps

# Install python-pptx if needed
pip3 install python-pptx lxml 2>/dev/null || true

# Remove any previous output file to prevent anti-gaming
rm -f /home/ga/Documents/presentations/meridian_pitch_final.pptx

# Record task start timestamp AFTER cleaning output files
date +%s > /tmp/rebrand_restructure_start_ts

# Ensure directories exist
mkdir -p /home/ga/Documents/presentations
mkdir -p /home/ga/Desktop

# Create the 25-slide consulting pitch deck with a data table on slide 12
# Data context: Realistic consulting engagement proposal for a fictional
# B2B SaaS company (NovaTech Systems). Financial figures are representative
# of mid-market enterprise software consulting engagements. Market data
# references real industry benchmarks (Gartner, McKinsey, BLS).
python3 << 'PYEOF'
import os
from pptx import Presentation
from pptx.util import Inches, Pt, Emu

PPTX_PATH = '/home/ga/Documents/presentations/apex_pitch_deck.pptx'

prs = Presentation()
prs.slide_width  = Emu(9144000)   # 10 inches
prs.slide_height = Emu(6858000)   # 7.5 inches

def get_layout(prs):
    """Return a layout with title (idx=0) and body (idx=1) placeholders."""
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

# ============================================================
# 25 slides — consulting pitch deck for NovaTech Systems
# "Apex Consulting Partners" appears in slides 1, 2, 3, 13, 25
# Table with 3 wrong values on slide 12
# "Our Team" section at slides 20-23
# ============================================================

slides_data = [
    # Slide 1 — Title
    ("Apex Consulting Partners \u2014 Strategic Growth Advisory",
     ["Q4 2024 Client Engagement Proposal",
      "Prepared for NovaTech Systems Board of Directors"]),

    # Slide 2 — Agenda
    ("Agenda",
     ["1. About Apex Consulting Partners",
      "2. Market Landscape & Industry Trends",
      "3. Client Challenge & Proposed Solution",
      "4. Implementation Roadmap",
      "5. Case Study: Revenue Impact",
      "6. Pricing & ROI",
      "7. Our Team",
      "8. Next Steps"]),

    # Slide 3 — About
    ("About Apex Consulting Partners",
     ["Founded 2009 in Boston, MA",
      "340+ consultants across 12 offices in North America, Europe, and Asia-Pacific",
      "Specializing in digital transformation, M&A integration, and operational excellence",
      "Recognized by Management Today as a Top 10 Boutique Consultancy three years running",
      "Client portfolio includes 47 Fortune 500 companies"]),

    # Slide 4 — Methodology
    ("Our Methodology",
     ["Five-phase engagement model: Discovery \u2192 Analysis \u2192 Strategy \u2192 Implementation \u2192 Measurement",
      "Average engagement duration: 8-14 months",
      "Cross-functional team of 6-12 consultants per engagement",
      "Weekly executive status updates and monthly steering committee reviews",
      "Knowledge transfer and capability building embedded in every phase"]),

    # Slide 5 — Market Landscape
    ("Market Landscape: Enterprise Software",
     ["Global enterprise software market: $672B in 2024, projected $1.1T by 2028",
      "CAGR: 11.2% driven by AI adoption and cloud migration",
      "Key trends: AI-driven automation, vertical SaaS consolidation, platform convergence",
      "Mid-market segment growing fastest at 14.3% annually",
      "Source: Gartner Market Analysis, September 2024"]),

    # Slide 6 — Industry Trends
    ("Industry Disruption Trends",
     ["47% of enterprises accelerating AI adoption timelines (McKinsey, Q3 2024)",
      "Cloud migration spending up 23% YoY, reaching $591B globally",
      "Cybersecurity investment reaching $215B by 2025 (IDC)",
      "Technical debt estimated at $1.5T across Fortune 500 companies",
      "71% of CIOs cite integration complexity as top barrier to transformation"]),

    # Slide 7 — Client Challenge
    ("Client Challenge: NovaTech Systems",
     ["Declining market share from 12.3% to 9.1% over 18 months",
      "Legacy monolith architecture limiting product release velocity to 2 per quarter",
      "Customer churn rate increased to 8.4% (industry benchmark: 5.2%)",
      "Board mandate: return to double-digit market share growth within 14 months",
      "Annual technology spend: $47M with 62% allocated to maintenance vs. innovation"]),

    # Slide 8 — Proposed Solution
    ("Proposed Solution Framework",
     ["Three-phase transformation program:",
      "  Phase 1: Stabilize (Months 1-3) \u2014 Stop the bleeding, quick wins",
      "  Phase 2: Modernize (Months 4-8) \u2014 Platform migration, architecture redesign",
      "  Phase 3: Accelerate (Months 9-14) \u2014 Growth engine, market expansion",
      "23 deliverables across 4 workstreams: Product, Technology, Operations, Go-to-Market"]),

    # Slide 9 — Roadmap
    ("Implementation Roadmap",
     ["14-month phased execution plan",
      "Executive sponsor: NovaTech CTO",
      "Governance: Biweekly steering committee, monthly board updates",
      "Risk mitigation: Parallel-run strategy for platform migration",
      "Change management: Dedicated workstream with communications plan"]),

    # Slide 10 — Phase 1
    ("Phase 1: Discovery & Assessment (Months 1-3)",
     ["40+ stakeholder interviews across C-suite, VP, and Director levels",
      "Complete technology architecture audit and dependency mapping",
      "Competitive analysis: 8 direct competitors and 12 adjacent market entrants",
      "Customer journey mapping with NPS deep-dive (n=2,400 customers)",
      "Deliverable: 120-page diagnostic report with prioritized recommendations"]),

    # Slide 11 — Phase 2
    ("Phase 2: Strategy Development (Months 4-8)",
     ["Market repositioning strategy: from enterprise platform to intelligent automation suite",
      "Product roadmap redesign: microservices architecture, API-first approach",
      "Organizational design: shift from functional to product-aligned teams",
      "Talent gap analysis: 24 critical hires identified across engineering and product",
      "Deliverable: Board-approved 3-year strategic plan"]),

    # Slide 12 — Case Study (TABLE — body is minimal, table added separately)
    ("Case Study: Revenue Impact",
     ["NovaTech Systems pilot engagement results (Q1-Q4 2024)"]),

    # Slide 13 — Testimonials (contains "Apex Consulting Partners")
    ("Case Study: Client Testimonials",
     ["The Apex Consulting Partners team transformed how we think about our go-to-market "
      "strategy. They didn't just deliver a report \u2014 they embedded change into our DNA.",
      "\u2014 Sarah Blackwell, CEO, DataStream Analytics (2023 engagement)",
      "",
      "Within 9 months, our product release velocity tripled. The ROI exceeded our most "
      "optimistic projections.",
      "\u2014 Marcus Wei, CTO, CloudBridge Solutions (2022 engagement)",
      "",
      "Apex Consulting Partners brought a level of analytical rigor we had never experienced.",
      "\u2014 Rebecca Torres, COO, FinServ Holdings (2024 engagement)"]),

    # Slide 14 — Pricing: Investment
    ("Pricing: Investment Overview",
     ["Total engagement value: $2.4M over 14 months",
      "Payment structure: 40% at initiation / 30% at mid-point / 30% at completion",
      "Travel and out-of-pocket expenses billed at cost with monthly cap of $35K",
      "Optional: Ongoing advisory retainer at $45K per month post-engagement",
      "Performance bonus clause: 10% of documented savings above $8M threshold"]),

    # Slide 15 — Pricing: Tiers
    ("Pricing: Tier Comparison",
     ["Essential Tier ($1.2M): Strategy and roadmap only \u2014 6-month engagement",
      "Professional Tier ($2.4M): Full transformation program \u2014 14-month engagement",
      "Enterprise Tier ($4.1M): Transformation + managed services \u2014 24-month engagement",
      "All tiers include: executive workshops, monthly reporting, knowledge transfer",
      "Enterprise tier adds: 2 embedded consultants, 24/7 support, quarterly board presentations"]),

    # Slide 16 — Pricing: ROI
    ("Pricing: ROI Projection",
     ["Projected breakeven: 18 months post-engagement-start",
      "3-year ROI: 340% (based on comparable engagements)",
      "Key ROI drivers: revenue acceleration (+$12M), cost reduction (-$6M), churn reduction (-$3M)",
      "Comparable benchmarks: Deloitte median 280%, McKinsey median 310%, BCG median 295%",
      "Conservative scenario (50th percentile): 220% 3-year ROI"]),

    # Slide 17 — Timeline
    ("Timeline & Key Milestones",
     ["Q1 2025: Discovery phase complete, diagnostic delivered",
      "Q2 2025: Strategy approved by board, Phase 2 launches",
      "Q3 2025: Platform migration begins, first microservices deployed",
      "Q4 2025: Performance validation, handoff to internal teams",
      "Q1 2026: 90-day post-engagement review and optimization"]),

    # Slide 18 — Risk
    ("Risk Assessment & Mitigation",
     ["Execution Risk: Mitigation via phased approach with go/no-go gates",
      "Talent Risk: Pre-identified bench of specialist contractors for critical roles",
      "Technology Risk: Parallel-run strategy; rollback capability at every stage",
      "Market Risk: Scenario planning for 3 economic conditions (growth, flat, recession)",
      "Change Management Risk: Dedicated communications workstream with weekly pulses"]),

    # Slide 19 — Success Metrics
    ("Success Metrics & KPIs",
     ["Revenue growth target: +15% year-over-year by Q4 2025",
      "Market share recovery: 12%+ (from current 9.1%)",
      "Net Promoter Score: 50+ (from current 31)",
      "Product release velocity: 8+ releases per quarter (from current 2)",
      "Operational efficiency: 20% cost reduction in technology maintenance spend"]),

    # Slide 20 — Our Team: Leadership
    ("Our Team: Leadership",
     ["Sarah Chen, Managing Partner",
      "  20 years in strategy consulting, ex-McKinsey (Partner, 2008-2016)",
      "  Led 40+ transformation engagements totaling $2B+ in client value created",
      "",
      "Marcus Rivera, Engagement Lead",
      "  15 years specializing in enterprise technology transformations",
      "  Former VP of Engineering at Salesforce; holds 3 patents in cloud architecture"]),

    # Slide 21 — Our Team: Senior Partners
    ("Our Team: Senior Partners",
     ["Dr. James Okonkwo, Technology Practice Lead",
      "  MIT PhD in Computer Science, 3 patents in distributed systems",
      "  Previously: CTO at CloudScale (acquired by Oracle, 2019)",
      "",
      "Lisa Yamamoto, Operations Excellence Lead",
      "  Led $500M+ restructuring programs across 6 industries",
      "  Lean Six Sigma Master Black Belt, certified TOGAF Enterprise Architect"]),

    # Slide 22 — Our Team: Industry Experts
    ("Our Team: Industry Experts",
     ["8 vertical practice leads covering:",
      "  Healthcare & Life Sciences \u2014 Dr. Amara Osei",
      "  Financial Services & Insurance \u2014 Robert Steinberg",
      "  Technology & Software \u2014 Priya Narayanan",
      "  Manufacturing & Industrial \u2014 Heinrich Weber",
      "  Energy & Utilities \u2014 Carmen Delgado",
      "  Retail & Consumer \u2014 Yuki Tanaka",
      "  Telecommunications \u2014 Omar Al-Rashid",
      "  Government & Public Sector \u2014 Patricia Owens"]),

    # Slide 23 — Our Team: Client Engagement
    ("Our Team: Client Engagement",
     ["Dedicated engagement manager assigned to every client",
      "24/7 executive hotline for urgent escalations",
      "Quarterly business reviews with C-suite stakeholders",
      "Knowledge transfer program: 40 hours of embedded training",
      "Post-engagement support: 90-day transition period included in all tiers"]),

    # Slide 24 — Next Steps
    ("Next Steps",
     ["1. Approve Statement of Work by March 15, 2025",
      "2. Kickoff workshop: March 22, 2025 (NovaTech HQ, Denver)",
      "3. Phase 1 team mobilization: April 1, 2025",
      "4. First steering committee meeting: April 14, 2025",
      "5. Diagnostic report delivery: June 30, 2025"]),

    # Slide 25 — Thank You (contains "Apex Consulting Partners" and old email)
    ("Thank You",
     ["Apex Consulting Partners",
      "contact@apexconsulting.com",
      "(555) 234-5678",
      "",
      "1200 Boylston Street, Suite 800",
      "Boston, MA 02215",
      "",
      "www.apexconsulting.com"]),
]

# Create all 25 slides
for title_text, body_lines in slides_data:
    add_slide(prs, title_text, body_lines)

# ============================================================
# Add data table to Slide 12 (0-indexed: 11)
# Table: 6 rows x 5 columns (header + 5 metric rows)
# 3 cells have WRONG values that agent must correct per memo:
#   Cell (2,2): "$14.9M" should be "$15.6M"  [Client Revenue (Post), Q2 2024]
#   Cell (3,1): "$1.2M"  should be "$1.8M"   [Revenue Uplift, Q1 2024]
#   Cell (3,3): "$2.9M"  should be "$3.3M"   [Revenue Uplift, Q3 2024]
# ============================================================

slide_12 = prs.slides[11]
table_shape = slide_12.shapes.add_table(
    rows=6, cols=5,
    left=Inches(0.5), top=Inches(2.0),
    width=Inches(9.0), height=Inches(4.2)
)
table = table_shape.table

table_data = [
    ["Metric",               "Q1 2024", "Q2 2024", "Q3 2024", "Q4 2024 (Proj)"],
    ["Client Revenue (Pre)",  "$12.3M",  "$12.8M",  "$13.5M",  "$14.2M"],
    ["Client Revenue (Post)", "$14.1M",  "$14.9M",  "$16.8M",  "$17.9M"],   # Q2 WRONG
    ["Revenue Uplift",        "$1.2M",   "$2.8M",   "$2.9M",   "$3.7M"],    # Q1 and Q3 WRONG
    ["Uplift %",              "14.6%",   "21.9%",   "24.4%",   "26.1%"],
    ["ROI Multiple",          "2.1x",    "3.2x",    "3.8x",    "4.2x"],
]

for r, row_data in enumerate(table_data):
    for c, val in enumerate(row_data):
        table.cell(r, c).text = val

prs.save(PPTX_PATH)

# Verify creation
fsize = os.path.getsize(PPTX_PATH)
assert fsize > 10000, f"PPTX too small: {fsize} bytes — creation failed"
print(f"Created {PPTX_PATH} ({fsize} bytes, {len(prs.slides)} slides)")
PYEOF

# Write the update memo on the Desktop
cat > /home/ga/Desktop/deck_update_memo.txt << 'MEMOEOF'
PITCH DECK UPDATE MEMO — March 2025
From: Managing Partner's Office
To: Client Engagement Team
Re: Rebrand and restructure for NovaTech board presentation
═══════════════════════════════════════════════════════════

The following changes must be completed before the NovaTech Systems
board presentation on March 20, 2025.

1. COMPANY REBRAND
   Change ALL instances of "Apex Consulting Partners" to
   "Meridian Strategy Group" throughout the entire presentation —
   in titles, body text, and contact information. Also update the
   email on the Thank You slide from "contact@apexconsulting.com"
   to "contact@meridianstrategy.com".

2. REVENUE TABLE CORRECTIONS
   The data table on the slide titled "Case Study: Revenue Impact"
   contains three draft figures that must be corrected:
   • Row "Client Revenue (Post)", Column "Q2 2024":  $14.9M → $15.6M
   • Row "Revenue Uplift", Column "Q1 2024":         $1.2M  → $1.8M
   • Row "Revenue Uplift", Column "Q3 2024":         $2.9M  → $3.3M

3. DECK RESTRUCTURING
   The Managing Partner wants to "lead with people." Move the four
   Our Team slides to immediately after the title slide. The slides
   to move are titled:
     • "Our Team: Leadership"
     • "Our Team: Senior Partners"
     • "Our Team: Industry Experts"
     • "Our Team: Client Engagement"
   Keep them in this order when moved.

4. NEW SLIDE: "Meridian Strategy Group: At a Glance"
   Insert a new slide as slide 2 (between the title slide and the
   Our Team section). Title it "Meridian Strategy Group: At a Glance"
   and include this key metrics table:

   Metric                  2023     2024 YTD
   ─────────────────────────────────────────
   Fortune 500 Clients     47       52
   Total Revenue            $340M    $285M
   Client Retention Rate    94%      96%
   Avg Engagement Value     $2.7M    $3.1M
   Employee NPS Score       72       78

5. CONFIDENTIALITY FOOTER
   Add the following footer to all slides except the title slide:
   CONFIDENTIAL — Meridian Strategy Group 2024

6. SAVE
   Save the final deck as:
     /home/ga/Documents/presentations/meridian_pitch_final.pptx
   Do NOT overwrite the original apex_pitch_deck.pptx.
MEMOEOF

# Set ownership
chown ga:ga /home/ga/Documents/presentations/apex_pitch_deck.pptx
chown ga:ga /home/ga/Desktop/deck_update_memo.txt
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/Desktop

# Launch WPS Presentation with the pitch deck
launch_wps_with_file "/home/ga/Documents/presentations/apex_pitch_deck.pptx"

# Wait for WPS to load (custom wait since file is not performance.pptx)
elapsed=0
while [ $elapsed -lt 90 ]; do
    dismiss_eula_if_present
    # Dismiss format-check or system-check dialogs
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "WPS Office"; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1280 630 click 1 2>/dev/null || true
        sleep 1
    fi
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "apex_pitch_deck"; then
        echo "WPS loaded apex_pitch_deck.pptx after ${elapsed}s"
        sleep 3
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

maximize_wps
sleep 2
take_screenshot /tmp/rebrand_restructure_start_screenshot.png

echo "=== rebrand_restructure_pitch_deck setup complete ==="
echo "apex_pitch_deck.pptx created (25 slides with table on slide 12)"
echo "Update memo placed on Desktop"
