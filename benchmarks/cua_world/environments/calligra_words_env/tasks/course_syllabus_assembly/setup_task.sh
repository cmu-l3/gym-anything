#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Course Syllabus Assembly Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/cs3301_syllabus.odt
rm -f /home/ga/Desktop/syllabus_formatting_guide.txt

# Create the formatting guide
cat > /home/ga/Desktop/syllabus_formatting_guide.txt << 'EOF'
WESTFIELD STATE UNIVERSITY
OFFICE OF ACADEMIC AFFAIRS
SYLLABUS FORMATTING GUIDELINES

All course syllabi must be formatted according to the following standards before distribution to students or submission to the department repository:

1. TITLE BLOCK
- The course title (e.g., "CS 3301: Data Structures and Algorithms") must be bold and at least 14pt font size.

2. COURSE INFORMATION
- Basic course information (Instructor, Office, Office Hours, Email, Lecture, Lab, Prerequisites, Textbook, Supplementary) must be organized into a 2-column table.

3. SECTION HEADINGS
- The 7 main sections of the syllabus must be formatted using the "Heading 1" style.
- Main sections: Course Description, Learning Outcomes, Course Schedule, Grading Policy, Course Policies, University Resources, Important Dates.

4. SUBSECTIONS
- The 6 subsections within Course Policies and University Resources must be formatted using the "Heading 2" style.
- Subsections: Academic Integrity, Attendance, Late Work, Accessibility, Tutoring, Mental Health.

5. TABLES
- The Course Schedule must be converted into a table (Week, Dates, Topic, Reading, Assignments) with at least 12 rows.
- The Grading Policy breakdown must be converted into a 2-column table showing components and percentages.
- All tables should be properly aligned.

6. BODY TEXT
- All body text paragraphs must use justified alignment.
- All body text must have a font size of at least 11pt.
EOF
chown ga:ga /home/ga/Desktop/syllabus_formatting_guide.txt

# Create unformatted syllabus
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("CS 3301: Data Structures and Algorithms")
add_paragraph("Fall 2025")
add_paragraph("Westfield State University — Department of Computer Science")
add_paragraph("")
add_paragraph("Instructor: Dr. Maria Chen")
add_paragraph("Office: Ely Hall Room 214")
add_paragraph("Office Hours: Tue/Thu 2:00–3:30 PM, or by appointment")
add_paragraph("Email: mchen@westfield.edu")
add_paragraph("Lecture: Mon/Wed/Fri 10:00–10:50 AM, Scanlon Hall 108")
add_paragraph("Lab: Thursday 1:00–2:50 PM, Ely Hall Computer Lab 105")
add_paragraph("Prerequisites: CS 2201 (Programming II) with grade C or higher")
add_paragraph("Textbook: \"Introduction to Algorithms\" by Cormen, Leiserson, Rivest, and Stein (4th Edition, MIT Press, 2022)")
add_paragraph("Supplementary: \"Algorithm Design Manual\" by Steven S. Skiena (3rd Edition, Springer, 2020)")
add_paragraph("")
add_paragraph("Course Description")
add_paragraph("This course provides a comprehensive introduction to the design and analysis of algorithms and data structures. Students will learn how to organize data efficiently and write algorithms that perform optimally. Topics include asymptotic notation, sorting algorithms, trees, hash tables, graph algorithms, dynamic programming, greedy algorithms, and an introduction to NP-completeness. Programming assignments will require implementing these structures in C++ or Java.")
add_paragraph("")
add_paragraph("Learning Outcomes")
add_paragraph("By the end of this course, students will be able to:")
add_paragraph("1. Analyze the time and space complexity of algorithms using Big-O notation.")
add_paragraph("2. Implement and apply fundamental data structures including binary search trees, hash tables, and graphs.")
add_paragraph("3. Design algorithms using divide-and-conquer, dynamic programming, and greedy approaches.")
add_paragraph("4. Understand the concept of NP-completeness and its implications for algorithm design.")
add_paragraph("")
add_paragraph("Course Schedule")
add_paragraph("Week 1 | Sep 3-5 | Introduction & Algorithm Analysis | CLRS Ch. 1-3 | Assignment 1 Released")
add_paragraph("Week 2 | Sep 8-12 | Divide and Conquer, Recurrences | CLRS Ch. 4 | Lab 1: Performance Measurement")
add_paragraph("Week 3 | Sep 15-19 | Sorting: Quicksort, Heapsort | CLRS Ch. 6-7 | Assignment 1 Due, Assignment 2 Released")
add_paragraph("Week 4 | Sep 22-26 | Linear Time Sorting, Hash Tables | CLRS Ch. 8, 11 | Lab 2: Hash Function Collision")
add_paragraph("Week 5 | Sep 29-Oct 3 | Binary Search Trees, Red-Black Trees | CLRS Ch. 12-13 | Assignment 2 Due, Assignment 3 Released")
add_paragraph("Week 6 | Oct 6-10 | B-Trees, Augmenting Data Structures | CLRS Ch. 14, 18 | Lab 3: Tree Balancing")
add_paragraph("Week 7 | Oct 13-17 | Midterm Review & Midterm Exam | | Midterm Exam (Oct 17)")
add_paragraph("Week 8 | Oct 20-24 | Dynamic Programming I | CLRS Ch. 15 | Assignment 3 Due")
add_paragraph("Week 9 | Oct 27-31 | Dynamic Programming II, Greedy Algorithms | CLRS Ch. 15-16 | Assignment 4 Released")
add_paragraph("Week 10 | Nov 3-7 | Elementary Graph Algorithms | CLRS Ch. 22 | Lab 4: Graph Traversals")
add_paragraph("Week 11 | Nov 10-14 | Minimum Spanning Trees | CLRS Ch. 23 | Assignment 4 Due")
add_paragraph("Week 12 | Nov 17-21 | Single-Source Shortest Paths (Dijkstra) | CLRS Ch. 24 | Assignment 5 Released")
add_paragraph("Week 13 | Nov 24-28 | All-Pairs Shortest Paths | CLRS Ch. 25 | Thanksgiving Break (No Class Nov 26-28)")
add_paragraph("Week 14 | Dec 1-5 | Maximum Flow | CLRS Ch. 26 | Assignment 5 Due, Assignment 6 Released")
add_paragraph("Week 15 | Dec 8-12 | NP-Completeness & Review | CLRS Ch. 34 | Assignment 6 Due")
add_paragraph("")
add_paragraph("Grading Policy")
add_paragraph("Programming Assignments (6): 30%")
add_paragraph("Midterm Exam: 20%")
add_paragraph("Final Exam: 25%")
add_paragraph("Lab Participation: 10%")
add_paragraph("Quizzes (weekly): 10%")
add_paragraph("Class Participation: 5%")
add_paragraph("")
add_paragraph("Course Policies")
add_paragraph("Academic Integrity")
add_paragraph("Students must adhere to the Westfield State University Academic Honesty Policy. While discussing concepts with peers is encouraged, all submitted code must be your own original work. Use of generative AI or copying code from the internet without attribution constitutes academic dishonesty and will result in a failing grade for the assignment or course.")
add_paragraph("Attendance")
add_paragraph("Regular attendance at lectures and labs is expected. You are responsible for all material covered in class.")
add_paragraph("Late Work")
add_paragraph("Assignments submitted late will incur a 10% penalty per day up to a maximum of 3 days. No assignments will be accepted after 3 days without prior approval.")
add_paragraph("")
add_paragraph("University Resources")
add_paragraph("Accessibility")
add_paragraph("If you require accommodations, please contact the Banacos Academic Center within the first two weeks of class.")
add_paragraph("Tutoring")
add_paragraph("Free peer tutoring for this course is available through the Computer Science Reading Room (Ely 218).")
add_paragraph("Mental Health")
add_paragraph("University counseling services are available free of charge. Please reach out if you are feeling overwhelmed.")
add_paragraph("")
add_paragraph("Important Dates")
add_paragraph("Add/Drop Deadline: September 15, 2025")
add_paragraph("Midterm Exam: October 17, 2025")
add_paragraph("Withdrawal Deadline: November 10, 2025")
add_paragraph("Final Exam: December 16, 2025, 10:00 AM - 12:00 PM")

doc.save("/home/ga/Documents/cs3301_syllabus.odt")
PYEOF

chown ga:ga /home/ga/Documents/cs3301_syllabus.odt
date +%s > /tmp/task_start_time.txt

launch_calligra_document "/home/ga/Documents/cs3301_syllabus.odt"

wait_for_window "Calligra Words" 30
sleep 2

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="