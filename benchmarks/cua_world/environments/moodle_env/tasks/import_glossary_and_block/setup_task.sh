#!/bin/bash
echo "=== Setting up Import Glossary and Block task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Moodle to be fully ready
wait_for_moodle 120

# 1. Generate the real Medical Terminology XML Data
echo "Generating Medical Glossary XML..."
mkdir -p /home/ga/Documents
cat > /tmp/generate_medical_xml.py << 'EOF'
import xml.etree.ElementTree as ET
from xml.dom import minidom

# Real medical terminology data
terms = [
    ("Erythrocyte", "A red blood cell that (in humans) is typically a biconcave disc without a nucleus. Erythrocytes contain the pigment hemoglobin, which imparts the red color to blood, and transport oxygen and carbon dioxide to and from the tissues."),
    ("Leukocyte", "A colorless cell that circulates in the blood and body fluids and is involved in counteracting foreign substances and disease; a white (blood) cell."),
    ("Tachycardia", "An abnormally rapid heart rate, typically defined as a resting heart rate over 100 beats per minute in adults."),
    ("Bradycardia", "An abnormally slow heart action, typically defined as a resting heart rate of under 60 beats per minute in adults."),
    ("Hypertension", "Abnormally high blood pressure. A state of great psychological stress."),
    ("Hypotension", "Abnormally low blood pressure."),
    ("Hepatitis", "A disease characterized by inflammation of the liver."),
    ("Nephropathy", "Disease of the kidneys caused by damage to the small blood vessels or to the units in the kidneys that clean the blood."),
    ("Neuropathy", "Disease or dysfunction of one or more peripheral nerves, typically causing numbness or weakness."),
    ("Myocardial Infarction", "Another term for heart attack. A sudden and sometimes fatal occurrence of coronary thrombosis, typically resulting in the death of part of a heart muscle."),
    ("Ischemia", "An inadequate blood supply to an organ or part of the body, especially the heart muscles."),
    ("Hypoxia", "Deficiency in the amount of oxygen reaching the tissues."),
    ("Cyanosis", "A bluish discoloration of the skin resulting from poor circulation or inadequate oxygenation of the blood."),
    ("Dyspnea", "Difficult or labored breathing."),
    ("Apnea", "Temporary cessation of breathing, especially during sleep."),
    ("Edema", "A condition characterized by an excess of watery fluid collecting in the cavities or tissues of the body."),
    ("Hemostasis", "The stopping of a flow of blood."),
    ("Thrombosis", "Local coagulation or clotting of the blood in a part of the circulatory system."),
    ("Embolism", "Obstruction of an artery, typically by a clot of blood or an air bubble."),
    ("Aneurysm", "An excessive localized enlargement of an artery caused by a weakening of the artery wall."),
    ("Atherosclerosis", "A disease of the arteries characterized by the deposition of plaques of fatty material on their inner walls."),
    ("Arteriosclerosis", "The thickening and hardening of the walls of the arteries, occurring typically in old age."),
    ("Phlebitis", "Inflammation of the walls of a vein."),
    ("Anemia", "A condition marked by a deficiency of red blood cells or of hemoglobin in the blood, resulting in pallor and weariness."),
    ("Leukemia", "A malignant progressive disease in which the bone marrow and other blood-forming organs produce increased numbers of immature or abnormal leukocytes."),
    ("Septicemia", "Blood poisoning, especially that caused by bacteria or their toxins."),
    ("Hyperglycemia", "An excess of glucose in the bloodstream, often associated with diabetes mellitus."),
    ("Hypoglycemia", "Deficiency of glucose in the bloodstream."),
    ("Glycosuria", "A condition characterized by an excess of sugar in the urine, typically associated with diabetes or kidney disease."),
    ("Polyuria", "Production of abnormally large volumes of dilute urine."),
    ("Polydipsia", "Abnormally great thirst as a symptom of disease (such as diabetes) or psychological disturbance."),
    ("Polyphagia", "Excessive eating from excess hunger or increased appetite."),
    ("Dysphagia", "Difficulty or discomfort in swallowing, as a symptom of disease."),
    ("Dyspepsia", "Indigestion."),
    ("Gastroenteritis", "Inflammation of the stomach and intestines, typically resulting from bacterial toxins or viral infection and causing vomiting and diarrhea."),
    ("Cholecystitis", "Inflammation of the gallbladder."),
    ("Cholelithiasis", "The formation of gallstones."),
    ("Cirrhosis", "A chronic disease of the liver marked by degeneration of cells, inflammation, and fibrous thickening of tissue."),
    ("Pancreatitis", "Inflammation of the pancreas."),
    ("Peritonitis", "Inflammation of the peritoneum, typically caused by bacterial infection either via the blood or after rupture of an abdominal organ."),
    ("Appendicitis", "A serious medical condition in which the appendix becomes inflamed and painful."),
    ("Colitis", "Inflammation of the lining of the colon."),
    ("Diverticulitis", "Inflammation of a diverticulum, especially in the colon, causing pain and disturbance of bowel function."),
    ("Hematuria", "The presence of blood in urine."),
    ("Proteinuria", "The presence of abnormal quantities of protein in the urine, which may indicate damage to the kidneys."),
    ("Dysuria", "Painful or difficult urination."),
    ("Oliguria", "The production of abnormally small amounts of urine."),
    ("Anuria", "Failure of the kidneys to produce urine."),
    ("Uremia", "A raised level in the blood of urea and other nitrogenous waste compounds that are normally eliminated by the kidneys."),
    ("Cystitis", "Inflammation of the urinary bladder."),
    ("Pyelonephritis", "Inflammation of the substance of the kidney as a result of bacterial infection."),
    ("Encephalitis", "Inflammation of the brain, caused by infection or an allergic reaction."),
    ("Meningitis", "Inflammation of the meninges caused by viral or bacterial infection.")
]

root = ET.Element("GLOSSARY")
info = ET.SubElement(root, "INFO")
name = ET.SubElement(info, "NAME")
name.text = "Medical Glossary Export"
intro = ET.SubElement(info, "INTRO")
intro.text = "A collection of core medical terms."

entries = ET.SubElement(root, "ENTRIES")

for concept, definition in terms:
    entry = ET.SubElement(entries, "ENTRY")
    c_elem = ET.SubElement(entry, "CONCEPT")
    c_elem.text = concept
    d_elem = ET.SubElement(entry, "DEFINITION")
    d_elem.text = f"<p>{definition}</p>"
    f_elem = ET.SubElement(entry, "FORMAT")
    f_elem.text = "1"
    a_elem = ET.SubElement(entry, "APPROVED")
    a_elem.text = "1"
    u_elem = ET.SubElement(entry, "USEDYNALINK")
    u_elem.text = "0"
    c_sens = ET.SubElement(entry, "CASESENSITIVE")
    c_sens.text = "0"
    f_match = ET.SubElement(entry, "FULLMATCH")
    f_match.text = "0"
    t_elem = ET.SubElement(entry, "TEACHERENTRY")
    t_elem.text = "1"

xml_str = minidom.parseString(ET.tostring(root)).toprettyxml(indent="  ")
with open("/home/ga/Documents/medical_glossary.xml", "w", encoding="utf-8") as f:
    f.write(xml_str)
EOF

python3 /tmp/generate_medical_xml.py
chown ga:ga /home/ga/Documents/medical_glossary.xml
chmod 644 /home/ga/Documents/medical_glossary.xml

# 2. Create the target Course (MED101) programmatically
echo "Creating Medical Terminology course (MED101)..."
cat > /tmp/create_course.php << 'EOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot.'/course/lib.php');

$cat = $DB->get_record('course_categories', array('idnumber'=>'SCI'));
if(!$cat) {
    $cat = array_values($DB->get_records('course_categories'))[0];
}

$course = new stdClass();
$course->fullname = 'Medical Terminology';
$course->shortname = 'MED101';
$course->category = $cat->id;
$course->summary = 'An introduction to the language of medicine.';
$course->visible = 1;

if (!$DB->record_exists('course', array('shortname' => 'MED101'))) {
    $course = create_course($course);
    echo "Course created with ID: " . $course->id . "\n";
} else {
    echo "Course already exists.\n";
}
EOF

sudo -u www-data php /tmp/create_course.php

# 3. Clean up any existing attempts
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='MED101'")
if [ -n "$COURSE_ID" ]; then
    # Clear glossaries in this course
    sudo -u www-data php -r "
        define('CLI_SCRIPT', true);
        require('/var/www/html/moodle/config.php');
        require_once(\$CFG->dirroot.'/course/lib.php');
        require_once(\$CFG->dirroot.'/mod/glossary/lib.php');
        \$cms = get_coursemodules_in_course('glossary', $COURSE_ID);
        foreach (\$cms as \$cm) {
            course_delete_module(\$cm->id);
        }
    " 2>/dev/null || true
    
    # Clear blocks in this course context
    CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=50 AND instanceid=$COURSE_ID")
    if [ -n "$CONTEXT_ID" ]; then
        moodle_query "DELETE FROM mdl_block_instances WHERE parentcontextid=$CONTEXT_ID AND blockname='random_glossary_ent'"
    fi
fi

# 4. Start Firefox directly to Moodle
echo "Starting Firefox..."
restart_firefox "http://localhost/course/view.php?name=MED101"

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="