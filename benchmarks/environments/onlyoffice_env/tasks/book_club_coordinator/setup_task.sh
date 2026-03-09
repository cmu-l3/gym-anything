#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Book Club Coordinator Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw information text file
INFO_FILE="$WORKSPACE_DIR/bookclub_info.txt"

cat > "$INFO_FILE" << 'INFOEOF'
MOUNTAIN VIEW BOOK CLUB - RAW NOTES

MEMBERS:
Sarah Chen - loves mystery/thriller, vegetarian, 555-0101
Marcus Johnson - sci-fi fan, no restrictions, 555-0102  
Elena Rodriguez - literary fiction, gluten-free, 555-0103
David Kim - historical fiction, no restrictions, 555-0104
Jennifer Wu - romance/contemporary, nut allergy (severe!), 555-0105
Thomas Anderson - non-fiction/biography, diabetic (low sugar), 555-0106
Maria Santos - fantasy, vegetarian, 555-0107
Robert Lee - mystery, no restrictions, 555-0108

UPCOMING MEETINGS:
March 15, 2025 - "The Midnight Library" by Matt Haig - hosted by Sarah Chen at her place (123 Oak St)
April 19, 2025 - "Project Hail Mary" by Andy Weir - Marcus Johnson hosting (456 Elm Ave)  
May 17, 2025 - "Circe" by Madeline Miller - Elena Rodriguez turn (789 Pine Rd)
June 21, 2025 - "The Seven Husbands of Evelyn Hugo" by Taylor Jenkins Reid - Jennifer Wu (321 Maple Dr)

NOMINATED BOOKS (voting in progress):
"The Song of Achilles" by Madeline Miller - Elena nominated - 5 votes - Fantasy/Historical
"Klara and the Sun" by Kazuo Ishiguro - Sarah suggested - 3 votes - Literary Fiction
"The Anthropocene Reviewed" by John Green - Thomas wants this - 6 votes - Essays/Non-fiction
"Mexican Gothic" by Silvia Moreno-Garcia - Maria's pick - 4 votes - Horror/Gothic
"Educated" by Tara Westover - Jennifer rec - 7 votes - Memoir
"The Lincoln Highway" by Amor Towles - David's suggestion - 2 votes - Historical Fiction

PAST BOOKS WE READ:
Jan 2025 - "Where the Crawdads Sing" by Delia Owens
  Discussion Q: How does isolation shape Kya's character?
  Discussion Q: What did the ending reveal about justice?

Dec 2024 - "Atomic Habits" by James Clear  
  Discussion Q: Which habit framework worked best for you?

Nov 2024 - "The Thursday Murder Club" by Richard Osman
  Discussion Q: How does age affect the characters' detective work?
  Discussion Q: Favorite character and why?

HOSTING ROTATION:
Sarah Chen - last hosted Nov 2024, coming up March 2025
Marcus Johnson - last hosted Oct 2024, coming up April 2025
Elena Rodriguez - last hosted Sept 2024, coming up May 2025  
David Kim - hasn't hosted since July 2024
Jennifer Wu - last hosted Dec 2024, coming up June 2025
Thomas Anderson - last hosted Aug 2024  
Maria Santos - hasn't hosted since June 2024
Robert Lee - never hosted yet (joined in August)

INSTRUCTIONS FOR COORDINATOR:
Create a professional handbook document titled "Mountain View Book Club - 2025 Handbook"
Organize all the above information into clear sections with tables where appropriate.
Make it easy for members to find meeting dates, see who's hosting, and track our reading history.
INFOEOF

chown ga:ga "$INFO_FILE"

echo "✅ Information file created at: $INFO_FILE"

# Create a minimal starter document
DOC_PATH="$WORKSPACE_DIR/BookClub_2025.docx"

cat > /tmp/create_bookclub_starter.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

doc = Document()

# Add a simple instruction paragraph
doc.add_paragraph("Book Club Coordinator Task")
doc.add_paragraph("")
doc.add_paragraph("Instructions: Create a comprehensive book club handbook using the information from bookclub_info.txt")
doc.add_paragraph("")
doc.add_paragraph("Required sections:")
doc.add_paragraph("1. Document title (centered, bold)")
doc.add_paragraph("2. Member Roster (table)")
doc.add_paragraph("3. Upcoming Reading Schedule (table)")
doc.add_paragraph("4. Book Nomination Pool (table)")
doc.add_paragraph("5. Past Discussions Archive")
doc.add_paragraph("6. Hosting Rotation Tracker (table)")
doc.add_paragraph("")
doc.add_paragraph("Remember to use proper formatting: bold headings, table borders, and italic text for book titles.")

doc.save(sys.argv[1])
print(f"Starter document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_bookclub_starter.py
python3 /tmp/create_bookclub_starter.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Starter document created at: $DOC_PATH"

# Launch ONLYOFFICE with the starter document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_bookclub_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_bookclub_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

# Show notification with instructions
su - ga -c "DISPLAY=:1 notify-send -t 12000 'Book Club Task' 'Create BookClub_2025.docx handbook using info from ~/Documents/bookclub_info.txt. Include 5 sections with tables and proper formatting.'" || true

echo "=== Book Club Coordinator Task Setup Complete ==="
echo "📝 Task Summary:"
echo "  - Reference file: $INFO_FILE"
echo "  - Target document: $DOC_PATH"
echo "  - Required: 5 sections with tables, proper formatting"
echo ""
echo "Expected sections:"
echo "  1. Title: 'Mountain View Book Club - 2025 Handbook' (centered, bold, 16pt)"
echo "  2. Member Roster (table with 8 members)"
echo "  3. Upcoming Reading Schedule (table with 4 meetings)"
echo "  4. Book Nomination Pool (table with 5+ books)"
echo "  5. Past Discussions Archive (3+ books with questions)"
echo "  6. Hosting Rotation Tracker (table with all members)"
echo ""
echo "Formatting requirements:"
echo "  - Bold section headings (14pt+)"
echo "  - Tables with visible borders and bold headers"
echo "  - At least one use of italic text (book titles)"