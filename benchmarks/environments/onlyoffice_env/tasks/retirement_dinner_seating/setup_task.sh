#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Retirement Dinner Seating Chart Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document with guest list and instructions
DOC_PATH="$WORKSPACE_DIR/retirement_seating_chart.docx"

cat > /tmp/create_seating_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
import sys

doc = Document()

# Title
title = doc.add_heading('Retirement Dinner Seating Chart', 0)
title.alignment = WD_ALIGN_PARAGRAPH.CENTER

# Event info
doc.add_paragraph('Event: Dorothy Martinez Retirement Appreciation Dinner')
doc.add_paragraph('Venue: Community Center Main Hall')
doc.add_paragraph('Total Guests: 40 people')
doc.add_paragraph('')

# Guest list section
doc.add_heading('GUEST LIST WITH CONSTRAINTS (Reference)', 1)

guest_info = """
===== ALL 40 CONFIRMED GUESTS =====
1. Dorothy Martinez (GUEST OF HONOR)
2. James Rodriguez
3. Maria Santos
4. Robert Chen (caregiver)
5. Susan Chen (caregiver)
6. Michael Torres
7. Lisa Wong
8. Dr. Patricia Adams (giving speech)
9. David Kim
10. Jennifer Lee
11. Carlos Mendoza
12. Amanda White
13. Thomas Brown
14. Sarah Johnson
15. Kevin O'Brien
16. Michelle Nguyen
17. Daniel Park
18. Emily Davis
19. Christopher Miller
20. Jessica Taylor
21. Matthew Wilson
22. Ashley Martinez
23. Andrew Garcia
24. Emma Garcia (8 years old)
25. Rachel Anderson
26. Noah Johnson (9 years old)
27. Brandon Thomas
28. Stephanie Moore
29. Justin Jackson
30. Lauren Martin
31. Ryan Thompson
32. Lily Patel (7 years old)
33. Nicole Harris
34. Eric Clark
35. Megan Lewis
36. Tyler Robinson
37. Samantha Walker
38. Jonathan Hall
39. Rebecca Allen
40. Nicholas Young

===== MANDATORY SEATING CONSTRAINTS =====
✓ Dorothy Martinez MUST be at Table 1 (guest of honor)
✓ Dr. Patricia Adams MUST be at Table 1 (giving speech)
✓ Robert Chen and Susan Chen MUST sit at the SAME table (caregivers)
✓ Michael Torres and Lisa Wong MUST be at DIFFERENT tables (divorced couple)
✓ Emma Garcia, Noah Johnson, and Lily Patel MUST all be at Table 5 (children's table near restrooms)

===== TABLE CAPACITIES =====
• Table 1 (Head Table): 10 seats
• Table 2: 8 seats
• Table 3: 8 seats
• Table 4: 8 seats
• Table 5 (Children's Table): 6 seats

Total: 40 seats for 40 guests
"""

doc.add_paragraph(guest_info)
doc.add_paragraph('')

# Instructions section
doc.add_heading('YOUR TASK: Create Table Assignments Below', 1)

instructions = doc.add_paragraph()
instructions.add_run('INSTRUCTIONS: ').bold = True
instructions.add_run('Organize all 40 guests across the 5 tables below. Make sure to follow ALL mandatory constraints listed above. Format this professionally - the venue coordinator needs to print and distribute this to staff.\n\n')

doc.add_paragraph('Delete this instruction section and create your seating chart here. Suggested format:')
doc.add_paragraph('')

# Example format
example = doc.add_heading('TABLE 1 - Head Table (10 seats)', 2)
doc.add_paragraph('1. [Guest Name]')
doc.add_paragraph('2. [Guest Name]')
doc.add_paragraph('...')
doc.add_paragraph('')

doc.add_heading('TABLE 2 (8 seats)', 2)
doc.add_paragraph('[Assign 8 guests here]')
doc.add_paragraph('')

doc.add_paragraph('[Continue with Tables 3, 4, and 5...]')
doc.add_paragraph('')
doc.add_paragraph('')

# Footer reminder
reminder = doc.add_paragraph()
reminder.add_run('REMEMBER: ').bold = True
reminder.add_run('Check all constraints before saving! Dorothy & Dr. Adams at Table 1, Chen couple together, Torres & Wong separated, all 3 kids at Table 5.')

doc.save(sys.argv[1])
print(f"Seating chart starter document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_seating_doc.py
python3 /tmp/create_seating_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Seating chart starter document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_seating_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_seating_task.log || true
    # Don't exit - task can still proceed
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    # Don't exit - task can still proceed
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Retirement Dinner Seating Chart Task Setup Complete ==="
echo ""
echo "📋 TASK SUMMARY:"
echo "  • Create seating chart for 40 guests across 5 tables"
echo "  • Table capacities: Table 1=10, Table 2=8, Table 3=8, Table 4=8, Table 5=6"
echo ""
echo "⚠️  MANDATORY CONSTRAINTS:"
echo "  1. Dorothy Martinez → Table 1"
echo "  2. Dr. Patricia Adams → Table 1"
echo "  3. Robert Chen + Susan Chen → Same table"
echo "  4. Michael Torres + Lisa Wong → Different tables"
echo "  5. Emma Garcia + Noah Johnson + Lily Patel → Table 5"
echo ""
echo "💾 Save to: $DOC_PATH"