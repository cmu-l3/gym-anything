#!/bin/bash
set -e
echo "=== Setting up lease template completion task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing Calligra instances
kill_calligra_processes
sleep 2

mkdir -p /home/ga/Documents

# Create the lease template document using Python + odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

paragraphs = [
    "COMMERCIAL LEASE AGREEMENT",
    "",
    "This Commercial Lease Agreement is entered into as of [EFFECTIVE_DATE], by and between [LANDLORD_NAME] (\"Landlord\") and [TENANT_NAME] (\"Tenant\").",
    "",
    "RECITALS",
    "",
    "WHEREAS, [LANDLORD_NAME] is the owner of certain real property located at [PROPERTY_ADDRESS] (the \"Premises\"); and",
    "",
    "WHEREAS, [TENANT_NAME] desires to lease the Premises from [LANDLORD_NAME] for the purpose of operating [PERMITTED_USE]; and",
    "",
    "WHEREAS, [LANDLORD_NAME] is willing to lease the Premises to [TENANT_NAME] under the terms and conditions set forth herein;",
    "",
    "NOW, THEREFORE, in consideration of the mutual covenants and agreements contained herein, and for other good and valuable consideration, the receipt and sufficiency of which are hereby acknowledged, the parties agree as follows:",
    "",
    "ARTICLE I: PREMISES AND TERM",
    "",
    "1.1 Premises",
    "",
    "[LANDLORD_NAME] hereby leases to [TENANT_NAME], and [TENANT_NAME] hereby leases from [LANDLORD_NAME], the real property located at [PROPERTY_ADDRESS] (the \"Premises\"), together with all improvements, fixtures, and appurtenances thereto. The Premises consists of approximately 3,200 square feet of commercial space suitable for [PERMITTED_USE].",
    "",
    "1.2 Term",
    "",
    "The lease term shall be [LEASE_TERM], commencing on [COMMENCEMENT_DATE] and expiring on [EXPIRATION_DATE] (the \"Term\"), unless sooner terminated in accordance with the provisions of this Agreement. [TENANT_NAME] shall have the option to renew this lease for one additional period of five (5) years, provided that [TENANT_NAME] provides written notice to [LANDLORD_NAME] at least one hundred eighty (180) days prior to the expiration of the initial Term.",
    "",
    "ARTICLE II: RENT AND SECURITY DEPOSIT",
    "",
    "2.1 Base Rent",
    "",
    "[TENANT_NAME] shall pay to [LANDLORD_NAME] a monthly base rent of [MONTHLY_RENT] (the \"Base Rent\"), payable in advance on the first day of each calendar month during the Term. The first month's rent shall be due and payable upon execution of this Agreement. If the [COMMENCEMENT_DATE] falls on a day other than the first day of a calendar month, the Base Rent for such partial month shall be prorated on a per diem basis. Rent shall be paid by check or electronic transfer to [LANDLORD_NAME] at [LANDLORD_ADDRESS], or to such other address as [LANDLORD_NAME] may designate in writing.",
    "",
    "Beginning on the first anniversary of the [COMMENCEMENT_DATE] and on each anniversary thereafter during the Term, the Base Rent shall increase by three percent (3%) over the Base Rent for the immediately preceding year. [TENANT_NAME] acknowledges that timely payment of rent is a material obligation under this Agreement.",
    "",
    "2.2 Security Deposit",
    "",
    "Upon execution of this Agreement, [TENANT_NAME] shall deposit with [LANDLORD_NAME] the sum of [SECURITY_DEPOSIT] as a security deposit (the \"Security Deposit\"). The Security Deposit shall be held by [LANDLORD_NAME] as security for the faithful performance by [TENANT_NAME] of all terms, covenants, and conditions of this Agreement. [LANDLORD_NAME] may apply all or any portion of the Security Deposit to remedy any default by [TENANT_NAME] or to repair damages to the Premises caused by [TENANT_NAME] beyond normal wear and tear. Within thirty (30) days after the expiration or termination of this Agreement and [TENANT_NAME]'s surrender of the Premises, [LANDLORD_NAME] shall return the Security Deposit to [TENANT_NAME], less any amounts applied in accordance with this Section and applicable California law.",
    "",
    "ARTICLE III: USE AND COMPLIANCE",
    "",
    "3.1 Permitted Use",
    "",
    "[TENANT_NAME] shall use the Premises solely for the purpose of [PERMITTED_USE] and for no other purpose without the prior written consent of [LANDLORD_NAME]. [TENANT_NAME] shall not use or permit the use of the Premises for any unlawful purpose and shall comply with all applicable federal, state, and local laws, ordinances, rules, and regulations in connection with its use and occupancy of the Premises, including but not limited to all health, safety, and environmental regulations, and all applicable licenses and permits required for the operation of [PERMITTED_USE].",
    "",
    "3.2 Compliance with Laws",
    "",
    "[TENANT_NAME] shall, at its sole cost and expense, comply with all laws, statutes, ordinances, rules, regulations, and requirements of all federal, state, county, and municipal authorities now in force, or which may hereafter be in force, pertaining to the Premises or [TENANT_NAME]'s use thereof, including without limitation the Americans with Disabilities Act (ADA), the Occupational Safety and Health Act (OSHA), and all applicable building, fire, and health codes. [TENANT_NAME] shall obtain and maintain at its own expense all permits and licenses required for the conduct of [PERMITTED_USE] at the Premises.",
    "",
    "ARTICLE IV: MAINTENANCE AND REPAIRS",
    "",
    "4.1 Landlord Obligations",
    "",
    "[LANDLORD_NAME] shall be responsible for maintenance and repair of the structural elements of the building, including the foundation, exterior walls, and roof, as well as the common areas, parking facilities, and building systems including HVAC, plumbing, and electrical systems serving the building generally. [LANDLORD_NAME] shall maintain the Premises in compliance with all applicable building codes and shall respond to repair requests from [TENANT_NAME] within a reasonable time, not to exceed ten (10) business days for non-emergency repairs.",
    "",
    "4.2 Tenant Obligations",
    "",
    "[TENANT_NAME] shall, at its sole cost and expense, maintain the interior of the Premises in good condition and repair, including all interior walls, ceilings, floors, windows, doors, and fixtures. [TENANT_NAME] shall be responsible for all repairs necessitated by the acts or omissions of [TENANT_NAME], its employees, agents, invitees, or licensees. [TENANT_NAME] shall not make any alterations, additions, or improvements to the Premises without the prior written consent of [LANDLORD_NAME], which consent shall not be unreasonably withheld.",
    "",
    "ARTICLE V: INSURANCE AND INDEMNIFICATION",
    "",
    "5.1 Insurance Requirements",
    "",
    "[TENANT_NAME] shall, at its sole cost and expense, maintain throughout the Term the following insurance coverages: (a) commercial general liability insurance with limits of not less than $1,000,000 per occurrence and $2,000,000 in the aggregate, naming [LANDLORD_NAME] as an additional insured; (b) property insurance covering [TENANT_NAME]'s personal property, inventory, fixtures, and improvements in an amount equal to their full replacement cost; and (c) workers' compensation insurance as required by applicable law. [TENANT_NAME] shall provide certificates of insurance to [LANDLORD_NAME] prior to the [COMMENCEMENT_DATE] and upon each renewal of such policies.",
    "",
    "5.2 Indemnification",
    "",
    "[TENANT_NAME] shall indemnify, defend, and hold harmless [LANDLORD_NAME] and its officers, directors, employees, agents, and representatives from and against any and all claims, damages, losses, costs, liabilities, and expenses (including reasonable attorneys' fees) arising out of or in connection with [TENANT_NAME]'s use and occupancy of the Premises, the conduct of [TENANT_NAME]'s business, or any act, omission, or negligence of [TENANT_NAME] or its employees, agents, contractors, invitees, or licensees. This indemnification obligation shall survive the expiration or termination of this Agreement.",
    "",
    "ARTICLE VI: DEFAULT AND REMEDIES",
    "",
    "ARTICLE VII: ASSIGNMENT AND SUBLETTING",
    "",
    "ARTICLE VIII: GENERAL PROVISIONS",
    "",
    "8.1 Quiet Enjoyment",
    "",
    "[LANDLORD_NAME] covenants that [TENANT_NAME], upon paying the rent and performing all of the terms, covenants, and conditions of this Agreement on [TENANT_NAME]'s part to be performed, shall peaceably and quietly enjoy the Premises during the Term without hindrance or interruption by [LANDLORD_NAME] or any person claiming by, through, or under [LANDLORD_NAME].",
    "",
    "8.2 Force Majeure",
    "",
    "Neither party shall be liable for any failure or delay in performing its obligations under this Agreement (other than the obligation to pay rent) to the extent that such failure or delay results from causes beyond the reasonable control of that party, including but not limited to acts of God, fire, flood, earthquake, epidemic, pandemic, war, terrorism, strikes, government orders, or other force majeure events.",
    "",
    "8.3 Governing Law",
    "",
    "This Agreement shall be governed by and construed in accordance with the laws of the State of California, without regard to its conflicts of laws principles. Any dispute arising out of or relating to this Agreement shall be resolved in the state or federal courts located in San Diego County, California.",
    "",
    "8.4 Severability",
    "",
    "If any provision of this Agreement is held to be invalid, illegal, or unenforceable, the validity, legality, and enforceability of the remaining provisions shall not be affected or impaired thereby.",
    "",
    "8.5 Waiver",
    "",
    "The waiver by either party of any breach of any provision of this Agreement shall not constitute a continuing waiver or a waiver of any subsequent breach of the same or a different provision of this Agreement.",
    "",
    "8.6 Notices",
    "",
    "All notices, demands, and other communications required or permitted under this Agreement shall be in writing and shall be deemed given when delivered personally, sent by certified mail (return receipt requested), or sent by overnight courier to the following addresses:",
    "",
    "To Landlord: [LANDLORD_NAME], [LANDLORD_ADDRESS]",
    "To Tenant: [TENANT_NAME], [TENANT_ADDRESS]",
    "",
    "8.7 Entire Agreement",
    "",
    "This Agreement constitutes the entire agreement between the parties with respect to the subject matter hereof and supersedes all prior negotiations, representations, warranties, commitments, offers, and agreements, whether written or oral. This Agreement may not be amended or modified except by a written instrument signed by both parties.",
    "",
    "IN WITNESS WHEREOF, the parties have executed this Commercial Lease Agreement as of the date first written above.",
    "",
    "LANDLORD:",
    "[LANDLORD_NAME]",
    "",
    "By: ___________________________",
    "Name: Sarah J. Mitchell",
    "Title: Managing Partner",
    "Date: ___________________________",
    "",
    "TENANT:",
    "[TENANT_NAME]",
    "",
    "By: ___________________________",
    "Name: David R. Chen",
    "Title: Chief Executive Officer",
    "Date: ___________________________"
]

for text in paragraphs:
    doc.text.addElement(P(text=text))

doc.save("/home/ga/Documents/commercial_lease.odt")
print("Document created successfully")
PYEOF

chown ga:ga /home/ga/Documents/commercial_lease.odt

# Launch Calligra Words with the document
launch_calligra_document "/home/ga/Documents/commercial_lease.odt"

# Wait for window
wait_for_window "commercial_lease\|Calligra Words\|calligrawords" 45

sleep 3

# Maximize and focus
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    wmctrl -ia "$WID" 2>/dev/null || true
fi

# Dismiss any dialogs
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Lease template completion task setup complete ==="