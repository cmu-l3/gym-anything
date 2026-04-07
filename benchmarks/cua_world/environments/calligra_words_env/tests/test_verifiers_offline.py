#!/usr/bin/env python3
"""Offline mock tests for all calligra_words_env verifiers.

Tests the do-nothing invariant: when the agent makes no changes,
every verifier must return passed=False.

Usage:
    python3 examples/calligra_words_env/tests/test_verifiers_offline.py
"""

import json
import os
import shutil
import sys
import tempfile

# Set up import paths
TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_DIR = os.path.dirname(TESTS_DIR)
TASKS_DIR = os.path.join(ENV_DIR, "tasks")
UTILS_DIR = os.path.join(ENV_DIR, "utils")
sys.path.insert(0, UTILS_DIR)

# We need odfpy to create test documents
from odf.opendocument import OpenDocumentText
from odf.style import ParagraphProperties, Style, TextProperties
from odf.text import H, P, Span

# ──────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────

def _load_task_json(task_name):
    path = os.path.join(TASKS_DIR, task_name, "task.json")
    with open(path) as f:
        return json.load(f)


def _make_mock_copy_from_env(local_odt_path):
    """Return a mock copy_from_env that copies a local test file."""
    def mock_copy(remote_path, dest_path):
        shutil.copy2(local_odt_path, dest_path)
    return mock_copy


def _make_env_info(local_odt_path):
    """Build a minimal env_info dict with mocked copy_from_env."""
    return {
        "copy_from_env": _make_mock_copy_from_env(local_odt_path),
        # VLM unavailable in offline tests
        "query_vlm": None,
        "get_final_screenshot": None,
    }


# ──────────────────────────────────────────────────────────────────
# Create do-nothing test documents
# ──────────────────────────────────────────────────────────────────

def create_plain_text_odt(paragraphs, save_path):
    """Create an ODF with all plain P elements (no formatting)."""
    doc = OpenDocumentText()
    for text in paragraphs:
        doc.text.addElement(P(text=text))
    doc.save(save_path, False)


def create_regulatory_compliance_do_nothing(save_path):
    """Unformatted ESA report — all plain paragraphs."""
    texts = [
        "Phase I Environmental Site Assessment",
        "Riverside Industrial Complex",
        "4500 Industrial Boulevard, Riverside, CA 92501",
        "",
        "Prepared for: Consolidated Development Group, LLC",
        "Prepared by: EnviroTech Solutions, Inc.",
        "Date: November 15, 2025",
        "Project Number: ES-2025-1847",
        "",
        "Executive Summary",
        "EnviroTech Solutions was retained by Consolidated Development Group to conduct a Phase I Environmental Site Assessment.",
        "The assessment identified recognized environmental conditions including petroleum hydrocarbons and underground storage tanks.",
        "",
        "Introduction",
        "Purpose and Scope",
        "The purpose of this Phase I ESA is to identify recognized environmental conditions per ASTM E1527.",
        "",
        "Site Description",
        "Site Location and Legal Description",
        "The subject property is located at 4500 Industrial Boulevard in Riverside.",
        "Current Use of the Property",
        "The property is currently vacant.",
        "",
        "Records Review",
        "Environmental Database Search",
        "A search of environmental databases was conducted.",
        "Historical Land Use Records",
        "Historical records were reviewed.",
        "",
        "Site Reconnaissance",
        "Interior Observations",
        "The site reconnaissance was conducted on October 15, 2025.",
        "Exterior Observations",
        "Exterior observations identified stressed vegetation.",
        "",
        "Interviews",
        "Interviews were conducted with the property owner.",
        "",
        "Evaluation",
        "Data Gaps",
        "Several data gaps were identified.",
        "Recognized Environmental Conditions",
        "Based on the findings of this Phase I ESA, chlorinated solvents were detected.",
        "",
        "Conclusions and Recommendations",
        "Based on the findings of this Phase I ESA, a Phase II investigation is recommended.",
        "",
        "Table 1: Environmental Database Summary",
        "Database | Search Distance | Findings",
        "CERCLIS | 0.5 miles | No listings",
    ]
    create_plain_text_odt(texts, save_path)


def create_manuscript_import_do_nothing(save_path):
    """Frankenstein manuscript with all deliberate errors still present."""
    doc = OpenDocumentText()

    # Error styles
    body_style = Style(name="BodyCorrect", family="paragraph")
    body_style.addElement(ParagraphProperties(textalign="justify"))
    body_style.addElement(TextProperties(fontsize="12pt", fontname="Liberation Serif"))
    doc.automaticstyles.addElement(body_style)

    h3_err = Style(name="Heading3Error", family="paragraph", parentstylename="Heading_20_3")
    h3_err.addElement(TextProperties(fontsize="14pt", fontweight="bold"))
    doc.automaticstyles.addElement(h3_err)

    h2_err = Style(name="Heading2Error", family="paragraph", parentstylename="Heading_20_2")
    h2_err.addElement(TextProperties(fontsize="16pt", fontweight="bold"))
    doc.automaticstyles.addElement(h2_err)

    fake_h = Style(name="FakeHeadingError", family="paragraph")
    fake_h.addElement(TextProperties(fontsize="20pt", fontweight="bold"))
    fake_h.addElement(ParagraphProperties(textalign="center"))
    doc.automaticstyles.addElement(fake_h)

    wrong_font = Style(name="WrongFontError", family="paragraph")
    wrong_font.addElement(ParagraphProperties(textalign="justify"))
    wrong_font.addElement(TextProperties(fontsize="12pt", fontname="Comic Sans MS"))
    doc.automaticstyles.addElement(wrong_font)

    wrong_align = Style(name="WrongAlignError", family="paragraph")
    wrong_align.addElement(ParagraphProperties(textalign="center"))
    wrong_align.addElement(TextProperties(fontsize="12pt", fontname="Liberation Serif"))
    doc.automaticstyles.addElement(wrong_align)

    bold_err = Style(name="BoldError", family="text")
    bold_err.addElement(TextProperties(fontweight="bold"))
    doc.automaticstyles.addElement(bold_err)

    h1_correct = Style(name="Heading1Correct", family="paragraph", parentstylename="Heading_20_1")
    h1_correct.addElement(TextProperties(fontsize="18pt", fontweight="bold"))
    doc.automaticstyles.addElement(h1_correct)

    # Letter 1 — H3 error
    doc.text.addElement(H(outlinelevel=3, stylename="Heading3Error", text="Letter 1"))
    doc.text.addElement(P(stylename="BodyCorrect", text="To Mrs. Saville, England"))
    doc.text.addElement(P(stylename="BodyCorrect", text="St. Petersburgh, Dec. 11th, 17\u2014"))

    doc.text.addElement(P(stylename="WrongAlignError", text=(
        "You will rejoice to hear that no disaster has accompanied the commencement "
        "of an enterprise which you have regarded with such evil forebodings."
    )))

    doc.text.addElement(P(stylename="WrongFontError", text=(
        "I am already far north of London, and as I walk in the streets of Petersburgh."
    )))

    doc.text.addElement(P(stylename="BodyCorrect", text=(
        "I try in vain to be persuaded that the pole is the seat of frost and desolation."
    )))

    # Missing italic: "paradise of my own creation"
    doc.text.addElement(P(stylename="BodyCorrect", text=(
        "I had a paradise of my own creation."
    )))

    # Letter 2 — fake heading (plain paragraph)
    doc.text.addElement(P(stylename="FakeHeadingError", text="Letter 2"))
    doc.text.addElement(P(stylename="WrongAlignError", text=(
        "This expedition has been the favourite dream of my early years."
    )))
    doc.text.addElement(P(stylename="WrongFontError", text=(
        "But it is a still greater evil to me that I am self-educated."
    )))

    # Wrong font + bold error "supernatural" + missing italic "Ancient Mariner"
    p = P(stylename="WrongFontError")
    p.addText("I shall certainly find no friend on the wide ocean. Ancient Mariner and its ")
    p.addElement(Span(stylename="BoldError", text="supernatural"))
    p.addText(" terrors.")
    doc.text.addElement(p)

    # Letter 3 — correct H1
    doc.text.addElement(H(outlinelevel=1, stylename="Heading1Correct", text="Letter 3"))
    doc.text.addElement(P(stylename="BodyCorrect", text="My dear Sister, I write a few lines in haste."))
    # Missing italic: "what can stop the determined heart"
    doc.text.addElement(P(stylename="BodyCorrect", text=(
        "What can stop the determined heart and resolved will of man?"
    )))

    # Letter 4 — H2 error
    doc.text.addElement(H(outlinelevel=2, stylename="Heading2Error", text="Letter 4"))
    doc.text.addElement(P(stylename="WrongAlignError", text=(
        "There is something at work in my soul which I do not understand."
    )))
    p = P(stylename="WrongFontError")
    p.addText("Last Monday I was invited to dine. Study of ")
    p.addElement(Span(stylename="BoldError", text="electricity"))
    p.addText(" and galvanism.")
    doc.text.addElement(p)

    # Chapter 1 — H3 error
    doc.text.addElement(H(outlinelevel=3, stylename="Heading3Error", text="Chapter 1"))
    doc.text.addElement(P(stylename="BodyCorrect", text=(
        "I am by birth a Genevese. Cornelius Agrippa and natural philosophy."
    )))
    # Missing italic "Prometheus" + bold error "magnetism"
    p = P(stylename="BodyCorrect")
    p.addText("We explored Prometheus and its connection to ")
    p.addElement(Span(stylename="BoldError", text="magnetism"))
    p.addText(".")
    doc.text.addElement(p)

    # Chapter 2 — correct H1
    doc.text.addElement(H(outlinelevel=1, stylename="Heading1Correct", text="Chapter 2"))
    # Missing italic "tabula rasa"
    doc.text.addElement(P(stylename="BodyCorrect", text=(
        "My education was neglected, yet I was passionately fond of reading. "
        "A tabula rasa of my own making."
    )))
    doc.text.addElement(P(stylename="BodyCorrect", text=(
        "Margaret Saville. North Pacific Ocean. St. Petersburgh."
    )))

    doc.save(save_path, False)


def create_grant_proposal_do_nothing(save_path):
    """Unformatted NSF proposal — all plain paragraphs."""
    texts = [
        "Biochar-Amended Bioretention Systems for Enhanced Stormwater Treatment in Urban Watersheds",
        "Principal Investigator: Dr. Elena Vasquez",
        "Department of Environmental Engineering",
        "Pacific Northwest University",
        "NSF Program: Environmental Engineering (CBET-1440)",
        "Requested Amount: $499,872",
        "",
        "Cover Page",
        "Project Summary",
        "Overview",
        "Urban stormwater runoff represents one of the most significant non-point source pollution challenges.",
        "Intellectual Merit",
        "The intellectual merit lies in advancing fundamental understanding of contaminant transport.",
        "Broader Impacts",
        "This research will directly impact urban water quality management practices.",
        "",
        "Table of Contents",
        "Project Description",
        "Introduction and Motivation",
        "Biochar is a carbon-rich material produced through pyrolysis of organic biomass.",
        "Background and Related Work",
        "Previous research on bioretention systems.",
        "Research Plan",
        "The proposed research will employ a mixed-methods approach combining laboratory experiments.",
        "Expected Outcomes",
        "Design guidelines for biochar-amended systems.",
        "Timeline and Milestones",
        "Year 1-3 milestones.",
        "",
        "References Cited",
        "[1] Davis, A.P., et al. (2009). Bioretention technology.",
        "",
        "Budget Justification",
        "Category | Year 1 | Year 2 | Year 3 | Total",
        "Senior Personnel | $45,000 | $46,350 | $47,741 | $139,091",
        "Equipment | $45,000 | $15,000 | $8,000 | $68,000",
        "Dr. Vasquez has over 15 years of experience.",
        "",
        "Biographical Sketch",
        "polycyclic aromatic hydrocarbons, heavy metals, green infrastructure, watershed",
    ]
    create_plain_text_odt(texts, save_path)


def create_board_minutes_do_nothing(save_path):
    """Board minutes with all contamination still present (properly formatted)."""
    doc = OpenDocumentText()

    # Styles matching the setup script
    h1_style = Style(name="Heading1", family="paragraph")
    h1_style.addElement(TextProperties(fontsize="16pt", fontweight="bold",
                                        fontsizecomplex="16pt", fontweightcomplex="bold",
                                        fontsizeasian="16pt", fontweightasian="bold"))
    h1_style.addElement(ParagraphProperties(margintop="0.4cm", marginbottom="0.2cm"))
    doc.styles.addElement(h1_style)

    title_style = Style(name="Title", family="paragraph")
    title_style.addElement(TextProperties(fontsize="18pt", fontweight="bold",
                                           fontsizecomplex="18pt", fontweightcomplex="bold",
                                           fontsizeasian="18pt", fontweightasian="bold"))
    title_style.addElement(ParagraphProperties(textalign="center"))
    doc.styles.addElement(title_style)

    body_style = Style(name="BodyText", family="paragraph")
    body_style.addElement(TextProperties(fontsize="12pt", fontsizecomplex="12pt", fontsizeasian="12pt"))
    body_style.addElement(ParagraphProperties(textalign="justify", marginbottom="0.2cm"))
    doc.styles.addElement(body_style)

    center_style = Style(name="CenterText", family="paragraph")
    center_style.addElement(TextProperties(fontsize="12pt", fontsizecomplex="12pt", fontsizeasian="12pt"))
    center_style.addElement(ParagraphProperties(textalign="center"))
    doc.styles.addElement(center_style)

    doc.text.addElement(P(stylename=title_style, text="MERIDIAN TECHNOLOGIES INC."))
    doc.text.addElement(P(stylename=center_style, text="Minutes of the Board of Directors Meeting"))
    doc.text.addElement(P(stylename=center_style, text="Q4 2025 — December 18, 2025"))
    doc.text.addElement(P(stylename=body_style, text=(
        "Directors Present: Robert Chen (Chairman), Sarah Mitchell, David Okafor, "
        "Patricia Reeves, James Thornton, Lisa Yamamoto"
    )))
    doc.text.addElement(P(stylename=body_style))

    doc.text.addElement(H(outlinelevel=1, stylename=h1_style, text="Call to Order"))
    doc.text.addElement(P(stylename=body_style, text="Chairman Robert Chen called the meeting to order at 9:00 AM PST."))

    doc.text.addElement(H(outlinelevel=1, stylename=h1_style, text="Approval of Previous Minutes"))
    doc.text.addElement(P(stylename=body_style, text="Director Mitchell moved to approve the minutes of the Q3 2025 meeting."))

    doc.text.addElement(H(outlinelevel=1, stylename=h1_style, text="Financial Report"))
    doc.text.addElement(P(stylename=body_style, text="The Board approved the 2026 capital expenditure budget of $200 million."))
    doc.text.addElement(P(stylename=body_style, text="The Board declared a quarterly dividend of $0.35 per share."))
    # CONTAMINATED
    doc.text.addElement(P(stylename=body_style, text=(
        "Walsh also shared preliminary Q4 revenue of $412 million based on unaudited projections."
    )))

    doc.text.addElement(H(outlinelevel=1, stylename=h1_style, text="Strategic Initiatives"))
    doc.text.addElement(P(stylename=body_style, text="The Advanced Analytics Platform continues to exceed adoption targets."))
    # CONTAMINATED: Project Falcon
    doc.text.addElement(P(stylename=body_style, text=(
        "Torres referred to the initiative internally as 'Project Falcon' and noted "
        "that the Project Falcon team has been expanded."
    )))
    # CONTAMINATED: CloudNest Systems
    doc.text.addElement(P(stylename=body_style, text=(
        "The Board discussed the potential acquisition of CloudNest Systems for approximately "
        "$78 million acquisition price."
    )))
    doc.text.addElement(P(stylename=body_style, text="The Board approved cybersecurity improvements."))

    doc.text.addElement(H(outlinelevel=1, stylename=h1_style, text="Legal and Compliance Update"))
    doc.text.addElement(P(stylename=body_style, text="The Henderson patent dispute was resolved through mediation."))
    # CONTAMINATED: attorney-client privilege
    doc.text.addElement(P(stylename=body_style, text=(
        "Chen advised that the pending litigation has a 60% probability of adverse outcome. "
        "She recommended settling for $4.2 million."
    )))
    doc.text.addElement(P(stylename=body_style, text="The annual audit by Ernst & Young is scheduled for January 2026."))

    doc.text.addElement(H(outlinelevel=1, stylename=h1_style, text="Human Resources and Compensation"))
    doc.text.addElement(P(stylename=body_style, text=(
        "The Board approved the appointment of Dr. James Park as Chief Technology Officer."
    )))
    # CONTAMINATED: executive compensation
    doc.text.addElement(P(stylename=body_style, text=(
        "CEO Torres's compensation: base salary of $875,000, annual bonus of $1.2 million, "
        "RSU grant of 50,000 shares."
    )))

    doc.text.addElement(H(outlinelevel=1, stylename=h1_style, text="New Business"))
    doc.text.addElement(P(stylename=body_style, text=(
        "The Board discussed the 2026 Annual Meeting of Shareholders."
    )))

    doc.text.addElement(H(outlinelevel=1, stylename=h1_style, text="Adjournment"))
    doc.text.addElement(P(stylename=body_style, text="Chairman Chen adjourned the meeting at 3:45 PM PST."))
    doc.text.addElement(P(stylename=body_style, text="Meridian Technologies Inc."))

    doc.save(save_path, False)


def create_technical_manual_do_nothing(save_path):
    """Unformatted technical manual — all plain paragraphs."""
    texts = [
        "NetWatch Pro v3.2",
        "Administrator Manual",
        "Nexus Systems Corp.",
        "Version 3.2 — Release Date: September 2025",
        "",
        "Introduction",
        "NetWatch Pro is an enterprise-grade network monitoring and management platform.",
        "NetWatch Pro v3.2 introduces enhanced SNMP v3 support.",
        "",
        "System Requirements",
        "Hardware Requirements",
        "Component: CPU — Minimum: 4 cores — Recommended: 8 cores",
        "Component: RAM — Minimum: 8 GB — Recommended: 16 GB",
        "Component: Disk — Minimum: 100 GB SSD — Recommended: 500 GB NVMe SSD",
        "Software Requirements",
        "Operating System: Red Hat Enterprise Linux 8/9, Ubuntu Server 20.04/22.04",
        "",
        "Installation",
        "Linux Installation",
        "Step 1: Download the installation package.",
        "Step 3: sudo ./install.sh --accept-license",
        "Windows Installation",
        "Step 1: Run the MSI installer.",
        "",
        "Configuration",
        "Global Configuration",
        "Parameter: nw.scan.interval — Default: 300 — Unit: seconds",
        "Parameter: nw.alert.threshold — Default: 3 — Unit: count",
        "Configure alert thresholds to match your organization's SLA requirements.",
        "Alert Configuration",
        "Alerts are configured through the web console.",
        "",
        "Command Reference",
        "Network Discovery Commands",
        "netwatch --discover --subnet 192.168.1.0/24",
        "Monitoring Commands",
        "netwatch --monitor --device 192.168.1.1 --metrics cpu,memory,bandwidth",
        "nw-config --set nw.scan.interval=120",
        "nw-service restart",
        "",
        "Troubleshooting",
        "Common Error Codes",
        "Error Code: E001 — Meaning: Device unreachable",
        "Error Code: E002 — Meaning: SNMP authentication failure",
        "Performance Tuning",
        "The discovery engine uses a combination of ICMP echo requests and SNMP queries.",
        "",
        "API Reference",
        "GET /api/v3/devices — List all monitored devices. Returns a JSON payload.",
        "POST /api/v3/alerts/rules — Create a new alert rule.",
        "REST API at port 8443. ICMP, bandwidth utilization, latency threshold.",
        "",
        "Appendix",
        "Supported SNMP MIBs: IF-MIB, HOST-RESOURCES-MIB",
    ]
    create_plain_text_odt(texts, save_path)


# ──────────────────────────────────────────────────────────────────
# Test runner
# ──────────────────────────────────────────────────────────────────

def run_test(task_name, create_doc_fn, verifier_module, verifier_func_name):
    """Run a do-nothing test for a single task."""
    tmp = tempfile.mkdtemp(prefix=f"test_{task_name}_")
    odt_path = os.path.join(tmp, "test_doc.odt")

    try:
        # Create the initial (unmodified) document
        create_doc_fn(odt_path)

        # Load task info
        task_info = _load_task_json(task_name)

        # Create env_info with mock
        env_info = _make_env_info(odt_path)

        # Import and run the verifier
        task_dir = os.path.join(TASKS_DIR, task_name)
        sys.path.insert(0, task_dir)
        try:
            # Import fresh
            if verifier_module in sys.modules:
                del sys.modules[verifier_module]
            mod = __import__(verifier_module)
            verify_fn = getattr(mod, verifier_func_name)
        finally:
            sys.path.pop(0)

        result = verify_fn([], env_info, task_info)
        return result
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    tests = [
        (
            "regulatory_compliance_report",
            create_regulatory_compliance_do_nothing,
            "verifier",
            "verify_regulatory_compliance_report",
        ),
        (
            "manuscript_import_cleanup",
            create_manuscript_import_do_nothing,
            "verifier",
            "verify_manuscript_import_cleanup",
        ),
        (
            "grant_proposal_formatting",
            create_grant_proposal_do_nothing,
            "verifier",
            "verify_grant_proposal_formatting",
        ),
        (
            "board_minutes_sanitization",
            create_board_minutes_do_nothing,
            "verifier",
            "verify_board_minutes_sanitization",
        ),
        (
            "technical_manual_structuring",
            create_technical_manual_do_nothing,
            "verifier",
            "verify_technical_manual_structuring",
        ),
    ]

    all_passed = True
    print("=" * 70)
    print("OFFLINE MOCK TESTS: Do-Nothing Invariant")
    print("=" * 70)

    for task_name, create_fn, mod_name, func_name in tests:
        print(f"\n--- {task_name} ---")
        try:
            result = run_test(task_name, create_fn, mod_name, func_name)
            passed = result.get("passed", True)
            score = result.get("score", 100)
            feedback = result.get("feedback", "")

            if passed:
                print(f"  FAIL: Do-nothing returned passed=True (score={score})")
                print(f"  Feedback: {feedback}")
                all_passed = False
            else:
                print(f"  OK: Do-nothing returned passed=False (score={score})")
                print(f"  Feedback: {feedback}")
        except Exception as e:
            print(f"  ERROR: {e}")
            import traceback
            traceback.print_exc()
            all_passed = False

    print("\n" + "=" * 70)
    if all_passed:
        print("ALL DO-NOTHING TESTS PASSED")
    else:
        print("SOME TESTS FAILED — see details above")
    print("=" * 70)

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
