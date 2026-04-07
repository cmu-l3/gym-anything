#!/bin/bash
echo "=== Setting up investor_pitch_audit task ==="

source /workspace/scripts/task_utils.sh

# Kill any running WPS instance
kill_wps

# Install python-pptx if needed
pip3 install python-pptx lxml 2>/dev/null || true

# Remove any previous output file to prevent anti-gaming
rm -f /home/ga/Documents/Q3_board_corrected.pptx

# Record task start timestamp AFTER cleaning output files
date +%s > /tmp/investor_pitch_audit_start_ts

# Create the financial_report.pptx with real macroeconomic data
# Data sources:
#   - US GDP Q3 2024: 2.8% annualized (BEA advance estimate, Oct 30, 2024, BEA-2024-49)
#   - US GDP Q2 2024: 3.0% annualized (BEA, Aug 29, 2024)
#   - US Unemployment Sep 2024: 4.1% (BLS, Oct 4, 2024)
#   - Fed Funds Rate Sep 2024: 4.75%-5.00% (FOMC, Sep 18, 2024)
#   - Consumer spending Q3 2024: +3.7% (BEA)
python3 << 'PYEOF'
import sys
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN

PPTX_PATH = '/home/ga/Documents/financial_report.pptx'

prs = Presentation()
prs.slide_width  = Emu(9144000)   # 10 inches
prs.slide_height = Emu(6858000)   # 7.5 inches

def get_layout(prs, idx=1):
    """Return a layout that has title (idx=0) and body (idx=1) placeholders."""
    for layout in prs.slide_layouts:
        phs = {ph.placeholder_format.idx for ph in layout.placeholders}
        if 0 in phs and 1 in phs:
            return layout
    return prs.slide_layouts[idx]

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

# NOTE: Slides 4, 7, 11, 18 (1-indexed) intentionally say "Q2 2024" (should be Q3 2024)
# Slide 16 (1-indexed) is a contaminating competitor slide

slides_data = [
    # Slide 1
    ("Meridian Technology Group\nQ3 2024 Investor Update",
     ["October 30, 2024", "Earnings Conference Call", "CONFIDENTIAL — NOT FOR DISTRIBUTION"]),

    # Slide 2  (agenda)
    ("Agenda",
     ["1. Q3 2024 Business & Financial Highlights",
      "2. Revenue and Margin Performance",
      "3. Customer & Product Metrics",
      "4. Outlook and Guidance",
      "5. Q&A"]),

    # Slide 3
    ("Q3 2024 Macroeconomic Context",
     ["US GDP Growth Q3 2024: +2.8% annualized (BEA, Oct 30 2024)",
      "US GDP Growth Q2 2024: +3.0% annualized (BEA, Aug 29 2024)",
      "US Unemployment Rate Sep 2024: 4.1% (BLS, Oct 2024)",
      "Federal Funds Rate: 4.75%–5.00% (FOMC, Sep 18 2024)",
      "Consumer Spending Growth Q3 2024: +3.7% (BEA)"]),

    # Slide 4 — INJECTED ERROR: "Q2 2024" in title (should be Q3 2024)
    ("Q2 2024 Financial Highlights",
     ["Total Revenue: $148.3M (+22% YoY)",
      "Subscription Revenue: $131.7M (+26% YoY)",
      "Gross Profit: $112.1M (75.6% gross margin)",
      "Operating Income: $18.4M (+41% YoY)",
      "Net Income: $14.2M (+38% YoY)",
      "Cash & Equivalents: $284M"]),

    # Slide 5
    ("Revenue Performance — Subscription vs. Services",
     ["Subscription Revenue: $131.7M (89% of total)",
      "Professional Services: $16.6M (11% of total)",
      "Annual Recurring Revenue (ARR): $534M (+28% YoY)",
      "Net Revenue Retention (NRR): 118%",
      "Customer expansion drove $38M in incremental ARR"]),

    # Slide 6
    ("Segment Revenue Breakdown",
     ["Enterprise (>1,000 employees): $89.2M (+31% YoY)",
      "Mid-Market (100–999 employees): $42.5M (+19% YoY)",
      "SMB (<100 employees): $16.6M (+8% YoY)",
      "Geographic: North America 74%, EMEA 18%, APAC 8%"]),

    # Slide 7 — INJECTED ERROR: "Q2 2024" in title (should be Q3 2024)
    ("Q2 2024 Gross Margin Analysis",
     ["Gross Margin: 75.6% (vs. 73.1% in Q3 2023)",
      "Subscription Gross Margin: 82.3%",
      "Services Gross Margin: 28.4%",
      "Year-over-year improvement: +250 bps",
      "Cost of revenue reduction driven by infrastructure optimization"]),

    # Slide 8
    ("Operating Expenses",
     ["R&D: $42.1M (28.4% of revenue)",
      "Sales & Marketing: $51.8M (34.9% of revenue)",
      "G&A: $18.3M (12.3% of revenue)",
      "Total OpEx: $112.2M (75.7% of revenue)",
      "Headcount: 1,247 FTEs (+18% YoY)"]),

    # Slide 9
    ("Cash Flow Summary",
     ["Operating Cash Flow: $31.4M",
      "Free Cash Flow: $24.7M (16.7% FCF margin)",
      "Capital Expenditures: $6.7M",
      "Cash & Short-term Investments: $284.2M",
      "No debt outstanding; $100M revolving credit facility undrawn"]),

    # Slide 10
    ("Balance Sheet Highlights — September 30, 2024",
     ["Total Assets: $621.4M",
      "Total Liabilities: $187.3M",
      "Total Stockholders' Equity: $434.1M",
      "Deferred Revenue: $124.6M (+22% YoY)",
      "Days Sales Outstanding (DSO): 48 days"]),

    # Slide 11 — INJECTED ERROR: "Q2 2024" in title (should be Q3 2024)
    ("Q2 2024 Customer Metrics",
     ["Total Customers: 4,218 (+24% YoY)",
      "Enterprise Customers (>$100K ARR): 387 (+38% YoY)",
      "New Customers Added in Q: 214",
      "Gross Dollar Retention Rate: 97.2%",
      "Net Promoter Score: 54 (industry benchmark: 38)"]),

    # Slide 12
    ("Product Innovation — Q3 2024 Launches",
     ["MeridianAI v3.0: Predictive analytics module released Sep 2024",
      "API v4: 40% latency reduction, 99.99% uptime SLA",
      "Mobile app refresh: 4.8/5 App Store rating",
      "SOC 2 Type II recertification completed",
      "HIPAA Business Associate Agreement (BAA) now available"]),

    # Slide 13
    ("Market Expansion — APAC & EMEA",
     ["APAC ARR grew 67% YoY to $42.7M",
      "New Singapore data center: opened August 2024",
      "EMEA headcount: +32 engineers added in Q3 2024",
      "Strategic partnerships: 3 new GSI agreements signed",
      "Channel revenue now 21% of total bookings"]),

    # Slide 14
    ("Strategic Partnerships & Ecosystem",
     ["AWS Marketplace: 1,400+ listings, ISV Accelerate partner",
      "Salesforce AppExchange: 5-star rating, 200K+ installs",
      "Microsoft Azure Marketplace: certified integration",
      "12 new system integrator partnerships in Q3 2024",
      "Partner-sourced revenue: 21% of new bookings"]),

    # Slide 15
    ("Risk Factors",
     ["Macroeconomic: potential enterprise budget tightening",
      "Competitive: continued pricing pressure in SMB segment",
      "Regulatory: EU AI Act and US data privacy legislation",
      "Execution: scaling international operations",
      "See Annual Report on Form 10-K for complete risk factors"]),

    # Slide 16 — CONTAMINATING SLIDE: competitor company
    ("Apex Digital Solutions — Company Overview",
     ["Apex Digital Solutions, Inc. | NASDAQ: APXD",
      "Founded 2011 | HQ: Austin, TX",
      "Q3 2024 Revenue: $89.4M | ARR: $341M",
      "Customers: 2,100 | NRR: 109%",
      "Note: This slide belongs to a different company's IR deck"]),

    # Slide 17
    ("Technology Platform — Architecture Overview",
     ["Multi-tenant SaaS on AWS (us-east-1, eu-west-1, ap-southeast-1)",
      "Microservices: 148 independently deployed services",
      "Uptime SLA: 99.95% (actual: 99.97% trailing 12 months)",
      "Data processed per day: 4.2 TB",
      "API calls per day: 1.8 billion"]),

    # Slide 18 — INJECTED ERROR: "Q2 2024" in title (should be Q3 2024)
    ("Q2 2024 Engineering & Headcount",
     ["Total Engineering FTEs: 512 (41% of total headcount)",
      "Engineering hires in quarter: 38 net new",
      "Attrition rate: 7.2% annualized (sector avg: 12.4%)",
      "R&D spend as % of revenue: 28.4%",
      "Employee NPS: 62 (Glassdoor: 4.3/5)"]),

    # Slide 19
    ("Data Center Infrastructure",
     ["3 primary regions: US-East, EU-West, AP-Southeast",
      "Disaster Recovery RTO: <4 hours, RPO: <1 hour",
      "AWS spend optimization: $2.1M savings in Q3 2024",
      "CDN egress costs reduced 18% via edge caching",
      "Infrastructure cost per $1 of ARR: $0.09 (improving)"]),

    # Slide 20
    ("Security & Compliance Posture",
     ["SOC 2 Type II: certified (annual audit)",
      "ISO 27001: certified since 2022",
      "GDPR: fully compliant; DPA agreements in place",
      "Penetration testing: conducted quarterly",
      "Bug Bounty program: $0 critical vulnerabilities in Q3 2024"]),

    # Slide 21
    ("ESG Overview",
     ["Carbon neutral operations since 2022 (Scope 1 & 2)",
      "100% renewable energy in US data centers (RECs)",
      "Diverse hiring: 48% of Q3 hires from underrepresented groups",
      "Charitable giving: $840K to STEM education in 2024 YTD",
      "ESG Report FY2023 published at investors.meridiantech.com"]),

    # Slide 22
    ("Corporate Governance",
     ["Board composition: 9 directors, 7 independent",
      "Committee chairs: Audit, Compensation, Nominating & Governance",
      "Board diversity: 44% women, 33% underrepresented minorities",
      "CEO/CFO certification of financial statements (SOX 302)",
      "Last investor day: March 2024"]),

    # Slide 23
    ("Board of Directors",
     ["Sarah Chen, Chairman (Lead Independent Director)",
      "Michael Torres, CEO & Director",
      "Patricia Okafor, CFO (not a Board member)",
      "David Ng, CTO (not a Board member)",
      "4 additional independent directors — see proxy statement"]),

    # Slide 24
    ("Executive Leadership Team",
     ["Michael Torres — Chief Executive Officer (joined 2018)",
      "Patricia Okafor — Chief Financial Officer (joined 2020)",
      "David Ng — Chief Technology Officer (joined 2019)",
      "Jennifer Walsh — Chief Revenue Officer (joined 2022)",
      "Hassan Ali — Chief Customer Officer (joined 2021)"]),

    # Slide 25
    ("Q4 2024 Outlook",
     ["Revenue guidance: $154M–$157M (+21%–23% YoY)",
      "Subscription revenue: $138M–$141M",
      "Non-GAAP operating income: $19M–$21M",
      "Non-GAAP EPS: $0.14–$0.16",
      "Based on current pipeline and macroeconomic assumptions"]),

    # Slide 26
    ("FY2024 Guidance (Updated)",
     ["FY2024 Revenue: $580M–$585M (raised from $575M–$582M)",
      "FY2024 Subscription Revenue: $517M–$521M",
      "FY2024 Non-GAAP Operating Income: $68M–$72M",
      "FY2024 FCF Margin: 14%–16%",
      "FY2024 Non-GAAP EPS: $0.52–$0.56"]),

    # Slide 27
    ("Long-Term Targets (3–5 Year)",
     ["Revenue target: $1.5B by FY2028",
      "Gross Margin target: 78%–80%",
      "Non-GAAP Operating Margin target: 20%–25%",
      "FCF Margin target: 18%–22%",
      "Net Revenue Retention target: >120%"]),

    # Slide 28
    ("Appendix A — Revenue Reconciliation",
     ["GAAP Revenue: $148.3M",
      "Deferred revenue adjustment: +$1.2M",
      "Non-GAAP Revenue: $149.5M",
      "Note: Non-GAAP adjustments per SEC Regulation G",
      "Full reconciliation tables available at IR website"]),

    # Slide 29
    ("Appendix B — Non-GAAP Reconciliation",
     ["GAAP Operating Income: $12.8M",
      "Stock-based compensation: +$4.9M",
      "Amortization of acquired intangibles: +$0.7M",
      "Non-GAAP Operating Income: $18.4M",
      "Non-GAAP Operating Margin: 12.4%"]),

    # Slide 30
    ("Thank You",
     ["Investor Relations Contact:",
      "Patricia Okafor, CFO | ir@meridiantech.com | +1 (415) 555-0192",
      "Meridian Technology Group, Inc.",
      "101 Technology Drive, Suite 500 | San Francisco, CA 94107",
      "Webcast replay available at investors.meridiantech.com"]),
]

for title_text, body_lines in slides_data:
    add_slide(prs, title_text, body_lines)

prs.save(PPTX_PATH)
print(f"Created {PPTX_PATH} with {len(prs.slides)} slides")
PYEOF

# Create the compliance requirements document
# NOTE: document does NOT name which specific slides have errors (very_hard pattern)
cat > /home/ga/Desktop/meridian_compliance.txt << 'DOCEOF'
MERIDIAN TECHNOLOGY GROUP
INVESTOR RELATIONS COMPLIANCE CHECKLIST
Prepared by: Legal & Compliance Team
Reference: SEC Regulation FD; Regulation S-K Item 10(b)
Date: October 30, 2024

COMPLIANCE FAILURES IDENTIFIED IN REVIEW

The following issues must be corrected before the presentation is distributed
to investors or used on the earnings call:

ISSUE 1 — QUARTER REFERENCE ERRORS
All slides in this presentation must consistently reference Q3 2024
(the quarter ended September 30, 2024). The compliance team identified
slides where the quarter reference reads "Q2 2024" instead of "Q3 2024."
You must locate and correct every instance of this error.

ISSUE 2 — COMPETITOR INFORMATION DISCLOSURE
The presentation appears to contain at least one slide with financial and
business information belonging to a competitor or third-party company that
is not Meridian Technology Group. Such disclosure could violate Regulation
FD and competitive confidentiality obligations. Identify and remove any
slide whose content describes a company other than Meridian Technology Group.

ISSUE 3 — MISSING FORWARD-LOOKING STATEMENTS DISCLAIMER
SEC guidance and standard IR practice require that any earnings presentation
containing forward-looking statements include a clearly titled
"Forward-Looking Statements" disclaimer slide. This slide should appear
IMMEDIATELY AFTER the title slide (as slide 2). The disclaimer must contain
the following exact text as the body:

"This presentation contains forward-looking statements within the meaning
of Section 27A of the Securities Act of 1933 and Section 21E of the
Securities Exchange Act of 1934. Forward-looking statements are subject
to risks and uncertainties that could cause actual results to differ
materially. Factors that may affect results include: macroeconomic
conditions, competitive dynamics, regulatory changes, execution risk, and
other factors detailed in Meridian Technology Group's filings with the
SEC. The company undertakes no obligation to update forward-looking
statements after the date of this presentation."

REQUIRED ACTION
Correct all three issues described above. Save the corrected presentation
as a NEW FILE at: /home/ga/Documents/Q3_board_corrected.pptx
Do NOT modify the original file at: /home/ga/Documents/financial_report.pptx
DOCEOF

chown ga:ga /home/ga/Documents/financial_report.pptx
chown ga:ga /home/ga/Desktop/meridian_compliance.txt
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# Launch WPS with the financial report
launch_wps_with_file "/home/ga/Documents/financial_report.pptx"

# Wait for WPS to load (custom wait since file is not performance.pptx)
elapsed=0
while [ $elapsed -lt 60 ]; do
    dismiss_eula_if_present
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "WPS Office"; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1280 630 click 1 2>/dev/null || true
        sleep 1
    fi
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "financial_report"; then
        echo "WPS loaded financial_report.pptx after ${elapsed}s"
        sleep 3
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

maximize_wps
sleep 2
take_screenshot /tmp/investor_pitch_audit_start_screenshot.png

echo "=== investor_pitch_audit setup complete ==="
echo "financial_report.pptx created and ready for review"
echo "Compliance requirements document placed on Desktop"
