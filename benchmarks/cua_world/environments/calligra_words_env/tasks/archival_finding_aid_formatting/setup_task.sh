#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Archival Finding Aid Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/sba_finding_aid.odt
rm -f /home/ga/Desktop/dacs_style_guide.txt

# Create style guide
cat > /home/ga/Desktop/dacs_style_guide.txt << 'EOF'
ARCHIVAL FINDING AID FORMATTING GUIDE (DACS COMPLIANT)

1. TITLE BLOCK
   - The main title ("Susan B. Anthony Papers") must be Centered, Bold, and at least 16pt font.

2. MAIN SECTIONS (DACS Elements)
   - Apply "Heading 1" style to the following 6 section titles:
     * Collection Summary
     * Administrative Information
     * Biographical Note
     * Scope and Content Note
     * Subject Terms
     * Container List

3. SERIES TITLES
   - Apply "Heading 2" style to the 4 Series titles located within the Scope and Content Note:
     * Series I: Correspondence
     * Series II: Diaries
     * Series III: Speeches and Writings
     * Series IV: Miscellany

4. NARRATIVE TEXT
   - Body paragraphs in the Biographical Note and Scope and Content Note must be Justified alignment.

5. SUBJECT TERMS
   - Convert the comma-separated list of subject terms into a proper Bulleted List.

6. CONTAINER LIST (CRITICAL)
   - Under the "Container List" heading, convert the raw pipe-separated (|) text into a 4-column Table.
   - The 4 columns should be: Box, Folder, Contents, Dates.
   - The top header row of the table must be Bold.
   - Remove the original raw pipe-separated text once the table is complete.
EOF
chown ga:ga /home/ga/Desktop/dacs_style_guide.txt

# Create ODT document entirely without styles using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_p(text=""):
    doc.text.addElement(P(text=text))

# Title Block
add_p("Susan B. Anthony Papers")
add_p("A Finding Aid to the Collection in the Library of Congress")
add_p("Manuscript Division, Library of Congress, Washington, D.C.")
add_p("2025")
add_p("")

# Collection Summary
add_p("Collection Summary")
add_p("Title: Susan B. Anthony Papers")
add_p("Span Dates: 1846-1906")
add_p("Creator: Anthony, Susan B. (Susan Brownell), 1820-1906")
add_p("Extent: 500 items; 7 containers; 2.8 linear feet")
add_p("Language: English")
add_p("Location: Manuscript Division, Library of Congress, Washington, D.C.")
add_p("")

# Administrative Information
add_p("Administrative Information")
add_p("Provenance: The papers of Susan B. Anthony, reformer and suffragist, were given to the Library of Congress by her niece, Lucy E. Anthony, between 1909 and 1940.")
add_p("Access: The papers of Susan B. Anthony are open to research. Researchers are advised to contact the Manuscript Reading Room prior to visiting.")
add_p("Copyright: Copyright in the unpublished writings of Susan B. Anthony in these papers and in other collections in the custody of the Library of Congress has been dedicated to the public.")
add_p("")

# Biographical Note
add_p("Biographical Note")
add_p("Susan Brownell Anthony was a prominent American civil rights leader and feminist who played a pivotal role in the 19th-century women's rights movement to introduce women's suffrage into the United States. Born into a Quaker family committed to social equality, she collected anti-slavery petitions at the age of 17. In 1856, she became the New York state agent for the American Anti-Slavery Society.")
add_p("In 1851, she met Elizabeth Cady Stanton, who became her lifelong friend and co-worker in social reform activities, primarily in the field of women's rights. Together they founded the New York Women's State Temperance Society after Anthony was prevented from speaking at a temperance conference because she was female. Anthony traveled extensively, giving as many as 75 to 100 speeches per year on women's rights.")
add_p("")

# Scope and Content Note
add_p("Scope and Content Note")
add_p("The papers of Susan B. Anthony span the years 1846-1906, with the bulk of the material dating from 1850 to 1900. The collection consists of correspondence, diaries, speeches, and miscellaneous items reflecting her lifelong dedication to women's suffrage, abolition, and temperance.")
add_p("")
add_p("Series I: Correspondence")
add_p("This series contains letters sent and received by Anthony. Prominent correspondents include Elizabeth Cady Stanton, Frederick Douglass, and Lucretia Mott.")
add_p("")
add_p("Series II: Diaries")
add_p("Contains pocket diaries kept by Anthony detailing her extensive travel schedules, meetings, and daily expenses.")
add_p("")
add_p("Series III: Speeches and Writings")
add_p("Drafts and final copies of her major addresses, including her famous speech after her 1872 arrest for voting.")
add_p("")
add_p("Series IV: Miscellany")
add_p("Includes photographs, scrapbooks, and newspaper clippings collected by Anthony.")
add_p("")

# Subject Terms
add_p("Subject Terms")
add_p("Abolitionists, African Americans--Civil rights, Suffragists, Women's rights, Temperance, New York (State)--History")
add_p("")

# Container List
add_p("Container List")
add_p("Box 1 | Folder 1-5 | Family Correspondence | 1846-1880")
add_p("Box 1 | Folder 6-10 | General Correspondence | 1850-1906")
add_p("Box 2 | Folder 1-3 | Personal Diaries | 1856-1893")
add_p("Box 2 | Folder 4-8 | Speeches and Addresses | 1860-1900")
add_p("Box 3 | Folder 1-2 | Photographs and Miscellany | 1885-1905")

doc.save("/home/ga/Documents/sba_finding_aid.odt")
PYEOF
chown ga:ga /home/ga/Documents/sba_finding_aid.odt

# Start Calligra Words
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/sba_finding_aid.odt >/tmp/calligra_words.log 2>&1 < /dev/null &"

# Wait for window
wait_for_window "Calligra Words\|sba_finding_aid" 30

# Maximize Window
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

# Record task start time immediately AFTER file creation (critical for anti-gaming checks)
date +%s > /tmp/task_start_time.txt
echo "=== Setup complete ==="