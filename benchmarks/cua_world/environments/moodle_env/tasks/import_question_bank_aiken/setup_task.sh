#!/bin/bash
set -e
echo "=== Setting up Import Question Bank task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Wait for Moodle to be fully ready
wait_for_moodle 120

# 1. Create the target course using Moodle's PHP API
echo "Creating Nursing 101 course..."
cat > /tmp/create_course.php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
global $DB;

$category = $DB->get_record('course_categories', array('name'=>'Science'), '*', IGNORE_MISSING);
if (!$category) {
    // Fallback to category 1 if Science wasn't created by main setup
    $category = $DB->get_record('course_categories', array('id'=>1));
}

$course = $DB->get_record('course', array('shortname'=>'NURS101'), '*', IGNORE_MISSING);
if (!$course) {
    $cdata = new stdClass();
    $cdata->fullname = 'Nursing 101: Cardiovascular Health';
    $cdata->shortname = 'NURS101';
    $cdata->category = $category->id;
    $cdata->visible = 1;
    $cdata->startdate = time();
    $cdata->format = 'topics';
    try {
        $course = create_course($cdata);
        echo "Course created successfully.\n";
    } catch (Exception $e) {
        echo "Error creating course: " . $e->getMessage() . "\n";
    }
} else {
    echo "Course already exists.\n";
}
PHPEOF

sudo -u www-data php /tmp/create_course.php

# 2. Generate the Aiken format text file on the Desktop
echo "Generating Aiken question bank file..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/cardiology_nclex_questions.txt << 'EOF'
A client with a myocardial infarction is developing cardiogenic shock. Which condition should the nurse carefully assess the client for?
A. Purulent sputum
B. Ventricular dysrhythmias
C. Bradycardia
D. Warm, flushed skin
ANSWER: B

The nurse is caring for a client with a history of heart failure. Which statement by the client indicates a need for further teaching?
A. "I will weigh myself every morning."
B. "I will sleep with three pillows."
C. "I can add salt to my food if it tastes bland."
D. "I will take my water pill in the morning."
ANSWER: C

A client is admitted with acute pericarditis. Which symptom is most characteristically associated with this condition?
A. Pain that worsens with deep breathing and improves when sitting up
B. Crushing chest pain that radiates to the jaw
C. Decreased heart rate and blood pressure
D. Absent peripheral pulses
ANSWER: A

The nurse is reviewing the electrocardiogram (ECG) of a client with hyperkalemia. Which ECG change should the nurse expect to note?
A. ST segment depression
B. Prominent U wave
C. Tall, peaked T waves
D. Prolonged PR interval
ANSWER: C

A client is prescribed lisinopril for hypertension. Which common side effect should the nurse instruct the client to report?
A. Visual disturbances
B. Persistent, dry cough
C. Ringing in the ears
D. Constipation
ANSWER: B

Which biomarker is the most specific indicator of myocardial muscle damage?
A. Myoglobin
B. Creatine kinase-MB (CK-MB)
C. Troponin I
D. Lactate dehydrogenase (LDH)
ANSWER: C

A client with deep vein thrombosis (DVT) is receiving a heparin infusion. Which medication should the nurse ensure is readily available?
A. Vitamin K
B. Protamine sulfate
C. Flumazenil
D. Naloxone
ANSWER: B

A client with angina pectoris is prescribed sublingual nitroglycerin. What instruction should the nurse provide?
A. Take one tablet every 15 minutes up to 5 doses
B. Store the medication in a clear plastic container
C. Replace the medication prescription every 6 months
D. Swallow the tablet with a full glass of water
ANSWER: C

The nurse notes ventricular fibrillation on a client's cardiac monitor. What is the nurse's immediate priority?
A. Administer epinephrine intravenously
B. Prepare for synchronized cardioversion
C. Initiate cardiopulmonary resuscitation (CPR)
D. Assess the client's blood pressure
ANSWER: C

Which finding is most strongly associated with right-sided heart failure?
A. Crackles in the lungs
B. Peripheral edema
C. Shortness of breath at night (PND)
D. Dry, hacking cough
ANSWER: B

A client is undergoing a treadmill stress test. For which finding should the nurse immediately terminate the test?
A. Heart rate reaches 120 beats per minute
B. Client reports mild fatigue
C. ST segment elevation on the ECG monitor
D. Blood pressure increases to 150/90 mmHg
ANSWER: C

The nurse is assessing a client with peripheral arterial disease (PAD). Which symptom is typical of this condition?
A. Warm, swollen legs
B. Intermittent claudication
C. Brownish discoloration of the lower legs
D. Bounding pedal pulses
ANSWER: B

Which instruction is crucial for a client being discharged with a permanent pacemaker?
A. "You cannot use a microwave oven."
B. "Avoid raising your arm on the pacemaker side above your shoulder for a few weeks."
C. "You will need to take antibiotics before any dental procedure."
D. "Your pulse should naturally drop below the pacemaker's set rate while sleeping."
ANSWER: B

A client with hypertension asks why they must take a thiazide diuretic. The nurse explains that this medication lowers blood pressure primarily by:
A. Decreasing heart rate
B. Dilating peripheral blood vessels
C. Reducing blood volume and sodium levels
D. Blocking angiotensin receptors
ANSWER: C

When assessing a client with infective endocarditis, the nurse notes painful, red nodules on the pads of the client's fingers and toes. The nurse documents this finding as:
A. Janeway lesions
B. Roth's spots
C. Osler's nodes
D. Splinter hemorrhages
ANSWER: C
EOF

chown ga:ga /home/ga/Desktop/cardiology_nclex_questions.txt

# 3. Launch Firefox and navigate to the Moodle login page
echo "Launching Firefox..."
restart_firefox "http://localhost/login/index.php"

# Wait for window and maximize
sleep 3
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
echo "Taking initial screenshot..."
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="