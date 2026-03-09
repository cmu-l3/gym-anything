#!/bin/bash
set -e
echo "=== Setting up Course Syllabus Create Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare directories and clean state
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/ENVS410_Syllabus_Fall2024.odt 2>/dev/null || true

# 2. create course_data.json
cat > /home/ga/Documents/course_data.json << 'JSONEOF'
{
  "course": {
    "number": "ENVS 410",
    "title": "Urban Ecology and Sustainability",
    "credits": 4,
    "section": "001",
    "semester": "Fall 2024",
    "meeting_times": "Tuesdays and Thursdays, 12:30 – 1:50 PM",
    "location": "Cramer Hall, Room 171",
    "crn": "48217"
  },
  "instructor": {
    "name": "Dr. Samira Al-Rashid",
    "title": "Associate Professor, Department of Environmental Science and Management",
    "office": "Science Research and Teaching Center (SRTC), Room 416",
    "email": "alrashid@pdx.edu",
    "phone": "(503) 725-4983",
    "office_hours": "Tuesdays 2:00 – 4:00 PM, Thursdays 10:00 – 11:30 AM, or by appointment"
  },
  "description": "This upper-division course examines cities as complex socio-ecological systems. Students will explore how ecological principles apply to urban environments, investigate the interactions between human activities and ecological processes in metropolitan landscapes, and analyze strategies for enhancing urban sustainability and resilience. Topics include urban climate dynamics, urban biodiversity, green infrastructure, ecosystem services valuation, and environmental justice. The course integrates lectures, field-based labs at Portland-area sites, critical reading of primary literature, and a semester-long independent research project.",
  "prerequisites": "ENVS 301 or BI 357, or instructor consent. Upper-division standing required.",
  "learning_outcomes": [
    "Describe the fundamental ecological processes that operate in urban environments, including nutrient cycling, energy flow, and species interactions in the context of built landscapes.",
    "Analyze urban heat island effects, stormwater dynamics, and air quality patterns using field-collected and publicly available environmental monitoring data.",
    "Evaluate the ecosystem services provided by urban green spaces, street trees, riparian corridors, and constructed wetlands, and articulate their economic and social value.",
    "Apply field sampling methods for vegetation surveys, soil characterization, and invertebrate biodiversity assessments in urban parks and greenways.",
    "Critically assess environmental justice dimensions of urban ecological planning, including the inequitable distribution of green space, pollution exposure, and climate vulnerability across neighborhoods.",
    "Design, execute, and present an independent research project investigating an urban ecology question relevant to the Portland metropolitan region."
  ],
  "textbooks": [
    {
      "type": "required",
      "citation": "Forman, R.T.T. (2014). Urban Ecology: Science of Cities. Cambridge University Press.",
      "isbn": "978-1107007000",
      "note": "Available at the PSU Bookstore and on reserve at Millar Library."
    },
    {
      "type": "required",
      "citation": "Beatley, T. (2011). Biophilic Cities: Integrating Nature into Urban Design and Planning. Island Press.",
      "isbn": "978-1597267151",
      "note": "Available at the PSU Bookstore."
    },
    {
      "type": "supplementary",
      "citation": "Grimm, N.B., et al. (2008). Global Change and the Ecology of Cities. Science, 319(5864), 756–760.",
      "note": "PDF available on D2L course site."
    }
  ],
  "weekly_schedule": [
    {"week": 1, "dates": "Sep 24 – Sep 26", "topic": "Introduction: Cities as Ecosystems", "readings": "Forman Ch. 1–2; Grimm et al. (2008)", "assignments": ""},
    {"week": 2, "dates": "Oct 1 – Oct 3", "topic": "History and Theory of Urban Ecology", "readings": "Forman Ch. 3; Pickett et al. (2001)", "assignments": "Reading Response 1 due Thu"},
    {"week": 3, "dates": "Oct 8 – Oct 10", "topic": "Urban Climate and Heat Island Effects", "readings": "Forman Ch. 6; Oke (1982)", "assignments": "Reading Response 2 due Thu"},
    {"week": 4, "dates": "Oct 15 – Oct 17", "topic": "Urban Hydrology and Stormwater Ecology", "readings": "Forman Ch. 7; Walsh et al. (2005)", "assignments": "Field Lab 1: Johnson Creek (Tue); RR 3 due Thu"},
    {"week": 5, "dates": "Oct 22 – Oct 24", "topic": "Urban Soils and Biogeochemistry", "readings": "Forman Ch. 8", "assignments": "Reading Response 4 due Thu"},
    {"week": 6, "dates": "Oct 29 – Oct 31", "topic": "Urban Biodiversity: Flora and Fauna", "readings": "Forman Ch. 9–10", "assignments": "Field Lab 1 Report due Tue; RR 5 due Thu"},
    {"week": 7, "dates": "Nov 5 – Nov 7", "topic": "Midterm Review (Tue) and Midterm Exam (Thu)", "readings": "Review Weeks 1–6", "assignments": "MIDTERM EXAM — Thu Nov 7"},
    {"week": 8, "dates": "Nov 12 – Nov 14", "topic": "Green Infrastructure", "readings": "Beatley Ch. 1–3", "assignments": "Field Lab 2: Bioswale inventory (Tue); RR 6 due Thu"},
    {"week": 9, "dates": "Nov 19 – Nov 21", "topic": "Urban Forestry and Canopy Analysis", "readings": "Beatley Ch. 4–5", "assignments": "RR 7 due Thu; Final Project Proposal due Thu"},
    {"week": 10, "dates": "Nov 26 – Nov 28", "topic": "Urban Wildlife Ecology", "readings": "Forman Ch. 11", "assignments": "Field Lab 2 Report due Tue; NO CLASS Thu (Thanksgiving)"},
    {"week": 11, "dates": "Dec 3 – Dec 5", "topic": "Pollinator Corridors", "readings": "Beatley Ch. 6–7", "assignments": "Field Lab 3: Forest Park (Tue); RR 8 due Thu"},
    {"week": 12, "dates": "Dec 10 – Dec 12", "topic": "Environmental Justice", "readings": "Wolch et al. (2014)", "assignments": "RR 9 due Thu"},
    {"week": 13, "dates": "Jan 7 – Jan 9", "topic": "Community-Based Ecological Monitoring", "readings": "Dickinson et al. (2012)", "assignments": "Field Lab 3 Report due Tue; RR 10 due Thu"},
    {"week": 14, "dates": "Jan 14 – Jan 16", "topic": "Ecosystem Services Valuation", "readings": "Forman Ch. 14", "assignments": "Field Lab 4: Campus mapping (Tue); RR 11 due Thu"},
    {"week": 15, "dates": "Jan 21 – Jan 23", "topic": "Student Project Presentations", "readings": "None", "assignments": "Field Lab 4 Report due Tue; Presentations"},
    {"week": 16, "dates": "Jan 28", "topic": "Course Synthesis", "readings": "Beatley Ch. 8–9", "assignments": "Final Project Report due Tue Jan 28"}
  ],
  "grading": {
    "components": [
      {"item": "Participation & Discussion", "weight": "10%", "points": 100},
      {"item": "Weekly Reading Responses", "weight": "15%", "points": 120},
      {"item": "Field Lab Reports", "weight": "25%", "points": 200},
      {"item": "Midterm Exam", "weight": "15%", "points": 150},
      {"item": "Final Project Proposal", "weight": "5%", "points": 50},
      {"item": "Final Project Report & Presentation", "weight": "30%", "points": 300}
    ],
    "scale": { "A": "93-100", "A-": "90-92", "B+": "87-89", "B": "83-86", "C": "73-76", "D": "60-69", "F": "<60" }
  },
  "policies": {
    "attendance": "Regular attendance is expected. More than three unexcused absences may result in a full letter grade reduction.",
    "late_work": "Late assignments will be penalized 10% per day. After 5 days, late assignments receive a zero.",
    "academic_integrity": "All work submitted must be your own. Plagiarism or cheating will result in a failing grade.",
    "technology": "Laptops allowed for note-taking. Phones must be silenced."
  },
  "university_policies": {
    "disability_resource_center": "If you have a disability and need accommodations, please contact the DRC at 503-725-4150.",
    "title_ix": "Portland State University prohibits discrimination based on sex or gender under Title IX.",
    "diversity_statement": "Portland State University is committed to fostering a welcoming and inclusive academic environment."
  }
}
JSONEOF
chown ga:ga /home/ga/Documents/course_data.json

# 3. Record start time for verification
date +%s > /tmp/task_start_time.txt

# 4. Launch Application (OpenOffice Writer)
# Kill any existing instances first
pkill -f soffice 2>/dev/null || true
sleep 2

echo "Launching Apache OpenOffice Writer..."
su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice"; then
        echo "OpenOffice window found"
        break
    fi
    sleep 1
done
sleep 5

# Maximize and Focus
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs (Welcome wizard, recovery, etc)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="