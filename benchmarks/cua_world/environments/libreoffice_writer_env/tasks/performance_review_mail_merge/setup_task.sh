#!/bin/bash
set -e
echo "=== Setting up Performance Review Mail Merge task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Delete stale output files BEFORE recording timestamp
rm -f /home/ga/Documents/performance_reviews_final.odt 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# -------------------------------------------------------------------
# Generate employee_data.csv
# -------------------------------------------------------------------
cat > /home/ga/Documents/employee_data.csv <<'CSVEOF'
FirstName,LastName,Department,Rating,GoalsCompleted,GoalsTarget,AttendanceRate,SalaryAdjustment,ManagerName
Sarah,Chen,Engineering,Exceeds Expectations,12,10,98,5500,James Rodriguez
Michael,Thompson,Sales,Meets Expectations,8,10,95,2000,Lisa Park
Amara,Okafor,Human Resources,Needs Improvement,4,10,82,0,David Kim
James,Kowalski,Engineering,Meets Expectations,9,10,96,1500,James Rodriguez
Priya,Sharma,Marketing,Exceeds Expectations,11,10,97,4800,Rachel Foster
Daniel,Mueller,Finance,Meets Expectations,7,10,93,0,Sophia Adams
Olivia,Jackson,Sales,Exceeds Expectations,10,10,99,6000,Lisa Park
Carlos,Rivera,Engineering,Meets Expectations,8,10,94,1800,James Rodriguez
Yuki,Tanaka,Marketing,Needs Improvement,5,10,85,0,Rachel Foster
Nathan,Williams,Finance,Exceeds Expectations,11,10,97,5200,Sophia Adams
Elena,Petrova,Human Resources,Meets Expectations,7,10,91,0,David Kim
Marcus,Brown,Sales,Meets Expectations,9,10,96,2500,Lisa Park
Aisha,Hassan,Engineering,Needs Improvement,3,10,78,0,James Rodriguez
Rebecca,O'Brien,Marketing,Exceeds Expectations,12,10,98,4500,Rachel Foster
Thomas,Andersen,Finance,Meets Expectations,8,10,93,1200,Sophia Adams
CSVEOF

chown ga:ga /home/ga/Documents/employee_data.csv
chmod 644 /home/ga/Documents/employee_data.csv

# -------------------------------------------------------------------
# Generate review_letter_template.odt using odfpy
# -------------------------------------------------------------------
cat > /tmp/create_template.py <<'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

paragraphs = [
    "March 15, 2025",
    "",
    "Dear [FIRST_NAME] [LAST_NAME],",
    "",
    "Re: Annual Performance Review - Fiscal Year 2024",
    "",
    "I am writing to provide your annual performance review for fiscal year 2024 in the [DEPARTMENT] department.",
    "",
    "Your performance this year has been exceptional. You have consistently exceeded expectations across all key performance indicators, demonstrating outstanding leadership and initiative. Your contributions have set a benchmark for excellence within your team and across the organization. We are deeply appreciative of your dedication and impact.",
    "",
    "You have met the expectations for your role this year, delivering solid and reliable performance. Your contributions have been valued by your team, and you have demonstrated competence in your core responsibilities. We encourage you to continue building on this foundation and to seek opportunities for growth in the coming year.",
    "",
    "Your performance this year has fallen below the expectations for your role. We have identified areas requiring significant improvement, and a Performance Improvement Plan will be developed collaboratively with your manager within the next 30 days. We are committed to supporting your development and providing the resources needed for success.",
    "",
    "During this review period, you completed [GOALS_COMPLETED] out of [GOALS_TARGET] assigned goals, and maintained an attendance rate of [ATTENDANCE_RATE]%.",
    "",
    "Based on your performance, a salary adjustment of $[SALARY_ADJUSTMENT] has been approved, effective at the beginning of the next fiscal quarter.",
    "",
    "Please schedule a follow-up meeting with your manager to discuss this review in detail.",
    "",
    "Sincerely,",
    "",
    "[MANAGER_NAME]",
    "Department Manager",
    "Meridian Technologies, Inc.",
]

for text in paragraphs:
    doc.text.addElement(P(text=text))

doc.save("/home/ga/Documents/review_letter_template.odt")
print("Template created successfully.")
PYEOF

python3 /tmp/create_template.py
rm -f /tmp/create_template.py

chown ga:ga /home/ga/Documents/review_letter_template.odt
chmod 644 /home/ga/Documents/review_letter_template.odt

# Record original document hash for anti-gaming
md5sum /home/ga/Documents/review_letter_template.odt | awk '{print $1}' > /tmp/original_doc_hash.txt

# -------------------------------------------------------------------
# Launch LibreOffice Writer with the template
# -------------------------------------------------------------------
pkill -f "soffice" || true
pkill -f "libreoffice" || true
sleep 2

su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/review_letter_template.odt > /tmp/writer.log 2>&1 &"

# Wait for Writer window to appear
echo "Waiting for LibreOffice Writer to open..."
WRITER_READY=false
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "Writer|review_letter"; then
        WRITER_READY=true
        break
    fi
    sleep 1
done

if [ "$WRITER_READY" = "false" ]; then
    echo "WARNING: LibreOffice Writer did not appear within 60 seconds"
fi

sleep 2

# Maximize and focus the Writer window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "Writer|review_letter" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    echo "Writer window maximized and focused: $WID"
else
    echo "WARNING: Could not find Writer window ID"
fi

sleep 1

# Dismiss any startup dialogs
safe_xdotool ga :1 key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Performance Review Mail Merge setup complete ==="
echo "Template: /home/ga/Documents/review_letter_template.odt"
echo "CSV Data: /home/ga/Documents/employee_data.csv"
echo "Expected Output: /home/ga/Documents/performance_reviews_final.odt"
