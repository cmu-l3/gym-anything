#!/bin/bash
# setup_task.sh — Legal PSA Finalization Task

source /workspace/scripts/task_utils.sh
chmod +x /workspace/tasks/legal_psa_finalization/export_result.sh 2>/dev/null || true

echo "=== Setting up Legal PSA Finalization Task ==="

sudo -u ga mkdir -p /home/ga/Documents

date +%s > /tmp/legal_psa_task_start
chown ga:ga /tmp/legal_psa_task_start 2>/dev/null || true

# Create psa_draft.docx — a raw, poorly-formatted draft with no styles,
# no formatted title, no footer, no proper signature block, no bold defined terms.
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches

doc = Document()

# Set standard margins (1 inch — fine for this task)
section = doc.sections[0]
section.left_margin = Inches(1.25)
section.right_margin = Inches(1.25)
section.top_margin = Inches(1.0)
section.bottom_margin = Inches(1.0)

def plain(text, bold=False, size=11):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.size = Pt(size)
    run.bold = bold
    return p

def heading_plain(text, size=12):
    """Add section heading as plain bold text (no style applied — agent must apply Heading styles)."""
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.size = Pt(size)
    run.bold = True
    return p

def sub_heading_plain(text):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.size = Pt(11)
    run.bold = True
    return p

# --- Title (plain, not formatted — agent must apply 14pt, bold, centered) ---
p = doc.add_paragraph()
run = p.add_run("PROFESSIONAL SERVICES AGREEMENT")
run.font.size = Pt(11)  # wrong size
run.bold = False        # not bold
# p.alignment intentionally left at default (not centered)

doc.add_paragraph("")

plain(
    "This Professional Services Agreement (this \"Agreement\") is entered into as of "
    "January 15, 2024 (the \"Effective Date\") by and between Vertex Analytics Corp., "
    "a Delaware corporation with its principal place of business at 888 Innovation Drive, "
    "Austin, TX 78701 (\"Client\"), and Meridian Data Solutions LLC, a Texas limited "
    "liability company with its principal place of business at 500 Congress Ave, Suite 1200, "
    "Austin, TX 78701 (\"Service Provider\"). Client and Service Provider are each referred "
    "to individually as a \"Party\" and collectively as the \"Parties.\""
)

doc.add_paragraph("")

# --- Section 1: Definitions ---
heading_plain("Definitions")
plain(
    "As used in this Agreement, the following terms shall have the meanings set forth below:"
)
doc.add_paragraph("")

sub_heading_plain("1.1 Definitions")
plain(
    "\"Services\" means the professional data analytics consulting, software development, "
    "and related technology services described in each Statement of Work (\"SOW\") executed "
    "by the Parties pursuant to this Agreement, including all tasks, activities, and work "
    "products specified therein."
)
plain(
    "\"Deliverables\" means all work product, reports, analyses, software, code, "
    "documentation, and other materials created, developed, or prepared by Service Provider "
    "in connection with the Services and specified as deliverables in an applicable SOW."
)
plain(
    "\"Confidential Information\" means any non-public information disclosed by one Party "
    "(the \"Disclosing Party\") to the other Party (the \"Receiving Party\"), whether "
    "disclosed orally, in writing, electronically, or by any other means, that is designated "
    "as confidential or that reasonably should be understood to be confidential given the "
    "nature of the information and the circumstances of disclosure."
)
plain(
    "\"Intellectual Property Rights\" means all present and future rights in and to "
    "patents, patent applications, trademarks, service marks, trade names, copyrights, "
    "trade secrets, know-how, moral rights, rights of publicity, and all other intellectual "
    "and industrial property rights of any sort throughout the world."
)
plain(
    "\"Force Majeure Event\" means any event or circumstance beyond the reasonable control "
    "of a Party, including, without limitation, acts of God, earthquakes, floods, fires, "
    "epidemics, pandemics, wars, terrorism, riots, civil disturbances, governmental actions, "
    "labor disputes, power failures, and telecommunications failures."
)
doc.add_paragraph("")

# --- Section 2: Scope of Services ---
heading_plain("Scope of Services")
sub_heading_plain("2.1 Services")
plain(
    "Service Provider shall perform the Services described in each SOW in a professional "
    "and workmanlike manner, using qualified personnel with the skills, knowledge, and "
    "experience necessary to perform such Services. Service Provider shall comply with all "
    "applicable laws, regulations, and industry standards in performing the Services."
)
sub_heading_plain("2.2 Statements of Work")
plain(
    "The Parties may execute one or more Statements of Work (each, an \"SOW\") that "
    "describe specific Services to be performed, Deliverables to be provided, timelines, "
    "milestones, and applicable fees. Each SOW shall be incorporated into and governed by "
    "this Agreement. In the event of any conflict between an SOW and this Agreement, "
    "this Agreement shall control unless the SOW expressly provides otherwise."
)
sub_heading_plain("2.3 Changes to Scope")
plain(
    "Either Party may request changes to the scope of Services by submitting a written "
    "change request to the other Party. No change to the scope of Services shall be "
    "effective unless agreed upon in a written amendment to the applicable SOW signed "
    "by authorized representatives of both Parties."
)
doc.add_paragraph("")

# --- Section 3: Fees and Payment ---
heading_plain("Fees and Payment")
sub_heading_plain("3.1 Fees")
plain(
    "Client shall pay Service Provider the fees specified in each SOW. Unless otherwise "
    "specified in an SOW, fees are quoted in U.S. dollars and are exclusive of applicable "
    "taxes, which shall be Client's responsibility."
)
sub_heading_plain("3.2 Invoicing and Payment Terms")
plain(
    "Service Provider shall submit invoices to Client monthly in arrears for Services "
    "performed during the preceding calendar month, unless the applicable SOW specifies "
    "a different invoicing schedule. Client shall pay each undisputed invoice within "
    "thirty (30) days of receipt. Amounts not paid when due shall accrue interest at "
    "the rate of 1.5% per month (or the maximum rate permitted by applicable law, "
    "whichever is less)."
)
sub_heading_plain("3.3 Expenses")
plain(
    "Client shall reimburse Service Provider for all reasonable, pre-approved out-of-pocket "
    "expenses incurred in connection with the Services, including travel, lodging, and meals. "
    "Service Provider shall submit expense reports with appropriate documentation within "
    "thirty (30) days of incurring such expenses."
)
doc.add_paragraph("")

# --- Section 4: Intellectual Property ---
heading_plain("Intellectual Property")
sub_heading_plain("4.1 Client Ownership of Deliverables")
plain(
    "Subject to Service Provider's receipt of full payment of all fees and expenses "
    "due under this Agreement, Service Provider hereby assigns to Client all right, "
    "title, and interest in and to all Deliverables, including all Intellectual "
    "Property Rights therein. Service Provider shall execute such additional documents "
    "and take such further actions as Client may reasonably request to effectuate "
    "such assignment."
)
sub_heading_plain("4.2 License to Pre-Existing IP")
plain(
    "To the extent Service Provider uses any pre-existing intellectual property, "
    "tools, methodologies, or software owned by or licensed to Service Provider "
    "(\"Background IP\") in connection with the Services or Deliverables, Service "
    "Provider hereby grants Client a non-exclusive, perpetual, irrevocable, "
    "royalty-free license to use, modify, and sublicense such Background IP solely "
    "to the extent necessary for Client to use the Deliverables for their intended purpose."
)
doc.add_paragraph("")

# --- Section 5: Confidentiality ---
heading_plain("Confidentiality")
sub_heading_plain("5.1 Obligations")
plain(
    "Each Party agrees: (a) to hold the other Party's Confidential Information in strict "
    "confidence using at least the same degree of care it uses to protect its own "
    "confidential information, but in no event less than reasonable care; (b) not to "
    "disclose Confidential Information to any third party without the prior written "
    "consent of the Disclosing Party; and (c) to use Confidential Information solely "
    "for purposes of performing its obligations or exercising its rights under this Agreement."
)
sub_heading_plain("5.2 Exceptions")
plain(
    "Confidential Information does not include information that: (a) is or becomes "
    "publicly known through no breach of this Agreement; (b) was rightfully known to "
    "the Receiving Party before disclosure; (c) is independently developed by the "
    "Receiving Party without use of Confidential Information; or (d) is required to "
    "be disclosed by law, court order, or government authority, provided the Receiving "
    "Party gives prompt written notice to the Disclosing Party and reasonably cooperates "
    "in seeking a protective order."
)
doc.add_paragraph("")

# --- Section 6: Representations and Warranties ---
heading_plain("Representations and Warranties")
plain(
    "Each Party represents and warrants that: (a) it has the legal capacity, power, "
    "and authority to enter into and perform this Agreement; (b) this Agreement "
    "constitutes a valid and binding obligation of such Party; and (c) its execution, "
    "delivery, and performance of this Agreement does not violate any applicable law "
    "or any agreement to which it is a party. Service Provider additionally warrants "
    "that the Services will be performed in a professional and workmanlike manner "
    "consistent with industry standards, and that to Service Provider's knowledge, "
    "the Deliverables will not infringe any third-party Intellectual Property Rights."
)
doc.add_paragraph("")

# --- Section 7: Limitation of Liability ---
heading_plain("Limitation of Liability")
plain(
    "IN NO EVENT SHALL EITHER PARTY BE LIABLE TO THE OTHER FOR ANY INDIRECT, INCIDENTAL, "
    "CONSEQUENTIAL, SPECIAL, EXEMPLARY, OR PUNITIVE DAMAGES ARISING OUT OF OR RELATED "
    "TO THIS AGREEMENT, INCLUDING LOSS OF REVENUE, LOSS OF PROFITS, LOSS OF BUSINESS, "
    "OR LOSS OF DATA, WHETHER BASED ON CONTRACT, TORT, STATUTE, OR ANY OTHER LEGAL "
    "THEORY, EVEN IF SUCH PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. "
    "EACH PARTY'S TOTAL CUMULATIVE LIABILITY ARISING OUT OF OR RELATED TO THIS AGREEMENT "
    "SHALL NOT EXCEED THE TOTAL FEES PAID OR PAYABLE BY CLIENT UNDER THE APPLICABLE SOW "
    "IN THE TWELVE (12) MONTHS PRECEDING THE CLAIM."
)
doc.add_paragraph("")

# --- Section 8: Indemnification ---
heading_plain("Indemnification")
plain(
    "Service Provider shall defend, indemnify, and hold harmless Client and its officers, "
    "directors, employees, and agents from and against any claims, damages, losses, "
    "liabilities, costs, and expenses (including reasonable attorneys' fees) arising "
    "out of or relating to: (a) Service Provider's breach of any representation, "
    "warranty, or obligation under this Agreement; (b) Service Provider's negligence "
    "or willful misconduct; or (c) any allegation that the Deliverables infringe any "
    "third-party Intellectual Property Rights. Client shall give Service Provider prompt "
    "written notice of any claim and shall cooperate with Service Provider in the defense "
    "of such claim at Service Provider's expense."
)
doc.add_paragraph("")

# --- Section 9: General Provisions ---
heading_plain("General Provisions")
sub_heading_plain("9.1 Term and Termination")
plain(
    "This Agreement commences on the Effective Date and continues until terminated. "
    "Either Party may terminate this Agreement upon thirty (30) days' written notice "
    "to the other Party. Either Party may terminate this Agreement immediately upon "
    "written notice if the other Party materially breaches this Agreement and fails "
    "to cure such breach within fifteen (15) days after receiving written notice "
    "specifying the breach in reasonable detail."
)
sub_heading_plain("9.2 Governing Law")
plain(
    "This Agreement is governed by and construed in accordance with the laws of the "
    "State of Texas, without regard to its conflict of laws provisions. Any dispute "
    "arising out of or relating to this Agreement shall be resolved by binding "
    "arbitration administered by JAMS in Austin, Texas, under its Commercial Arbitration "
    "Rules, except that either Party may seek injunctive relief in any court of "
    "competent jurisdiction."
)
sub_heading_plain("9.3 Entire Agreement")
plain(
    "This Agreement, together with all executed SOWs, constitutes the entire agreement "
    "between the Parties with respect to its subject matter and supersedes all prior "
    "agreements, representations, and understandings, whether written or oral. "
    "This Agreement may be amended only by a written instrument signed by authorized "
    "representatives of both Parties. No waiver of any provision of this Agreement "
    "shall be effective unless in writing and signed by the waiving Party."
)
doc.add_paragraph("")

# --- Signature Block (plain text — agent must format as 2-column borderless table) ---
heading_plain("IN WITNESS WHEREOF")
plain(
    "the Parties have executed this Professional Services Agreement as of the Effective Date."
)
doc.add_paragraph("")
plain("CLIENT: Vertex Analytics Corp.")
plain("By: ____________________________")
plain("Name: ____________________________")
plain("Title: ____________________________")
plain("Date: ____________________________")
doc.add_paragraph("")
plain("SERVICE PROVIDER: Meridian Data Solutions LLC")
plain("By: ____________________________")
plain("Name: ____________________________")
plain("Title: ____________________________")
plain("Date: ____________________________")

doc.save("/home/ga/Documents/psa_draft.docx")
print("Created psa_draft.docx")
PYEOF

sudo chown ga:ga /home/ga/Documents/psa_draft.docx
sudo chmod 664 /home/ga/Documents/psa_draft.docx

echo "Launching LibreOffice Writer with psa_draft.docx..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/psa_draft.docx > /tmp/writer_psa_task.log 2>&1 &"

if ! wait_for_process "soffice" 20; then
    echo "ERROR: LibreOffice failed to start"
fi

if ! wait_for_window "LibreOffice Writer" 90; then
    wait_for_window "psa_draft" 30 || true
fi

sleep 2

wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    safe_xdotool ga :1 key Escape
    sleep 0.3
    safe_xdotool ga :1 key ctrl+Home
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Take initial screenshot using ImageMagick import (scrot not in root PATH)
import -window root /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Legal PSA Finalization Task Setup Complete ==="
echo "Source document: /home/ga/Documents/psa_draft.docx"
echo "Required output: /home/ga/Documents/psa_final.docx"
exit 0
