#!/bin/bash
echo "=== Setting up build_patient_triage_system task ==="

source /workspace/scripts/task_utils.sh

# Clean stale outputs from previous runs
rm -f /tmp/triage_result.json /tmp/triage_initial.png /tmp/triage_final.png 2>/dev/null

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Seed patient intake form tiddlers
echo "Creating patient intake form tiddlers..."

cat << 'EOF' > "$TIDDLER_DIR/Intake Form - Maria Santos.tid"
title: Intake Form - Maria Santos
tags: IntakeForm
patient-name: Maria Santos
age: 67
chief-complaint: Acute chest pain radiating to left arm, onset 2 hours ago
temperature: 39.8
heart-rate: 112
blood-pressure: 165/95

!! Patient Intake Record

Maria Santos, 67-year-old female, presented to urgent care at 14:22 with acute chest pain radiating to the left arm. Pain began approximately 2 hours ago while climbing stairs at home. Patient describes the pain as a heavy, crushing sensation rated 8/10 on the pain scale.

!!! Associated Symptoms
* Shortness of breath (dyspnea) at rest
* Profuse sweating (diaphoresis)
* Nausea without vomiting
* Lightheadedness

!!! Medical History
* Hypertension — diagnosed 2014, managed with Lisinopril 10mg daily
* Type 2 Diabetes Mellitus — diagnosed 2018, managed with Metformin 500mg twice daily
* Hyperlipidemia — managed with Atorvastatin 20mg daily
* No prior cardiac events
* No surgical history

!!! Social History
* Non-smoker (quit 2010 after 20 pack-years)
* Occasional alcohol use
* Lives alone, independent in ADLs
* Retired school administrator

!!! Current Medications
|!Medication |!Dose |!Frequency |
|Lisinopril |10mg |Once daily |
|Metformin |500mg |Twice daily |
|Atorvastatin |20mg |Once daily at bedtime |
|Aspirin |81mg |Once daily |
EOF

cat << 'EOF' > "$TIDDLER_DIR/Intake Form - James Wilson.tid"
title: Intake Form - James Wilson
tags: IntakeForm
patient-name: James Wilson
age: 34
chief-complaint: Left ankle injury from basketball, swelling and difficulty walking
temperature: 37.1
heart-rate: 78
blood-pressure: 122/78

!! Patient Intake Record

James Wilson, 34-year-old male, presented to urgent care at 15:05 with a left ankle injury sustained during a recreational basketball game approximately 3 hours ago. Patient reports landing awkwardly after a jump shot and hearing an audible pop from the ankle joint.

!!! Presenting Complaints
* Moderate to severe swelling over the lateral malleolus
* Difficulty bearing weight on the left foot
* Pain rated 6/10, worsening with movement
* No numbness or tingling in the foot or toes

!!! Physical Examination Findings
* Edema and ecchymosis over lateral ankle
* Tenderness on palpation of the anterior talofibular ligament
* Positive anterior drawer test (mild laxity)
* Intact dorsalis pedis and posterior tibial pulses
* Sensation intact in all distributions

!!! Medical History
* No prior ankle injuries or fractures
* No chronic medical conditions
* No known drug allergies
* Immunizations up to date including tetanus (2022)

!!! Social History
* Software engineer, sedentary desk work
* Plays recreational basketball twice weekly
* Non-smoker, social alcohol use
* No illicit drug use
EOF

cat << 'EOF' > "$TIDDLER_DIR/Intake Form - Aisha Patel.tid"
title: Intake Form - Aisha Patel
tags: IntakeForm
patient-name: Aisha Patel
age: 45
chief-complaint: Severe thunderclap headache with visual disturbances, sudden onset
temperature: 37.4
heart-rate: 96
blood-pressure: 180/110

!! Patient Intake Record

Aisha Patel, 45-year-old female, presented to urgent care at 13:47 via walk-in with sudden onset severe headache that began approximately 45 minutes ago while at her desk at work. Patient describes the headache as the worst headache of my life, reaching maximum intensity within seconds of onset.

!!! Presenting Complaints
* Severe headache, 10/10 pain intensity, occipital region
* Photophobia — unable to tolerate overhead fluorescent lighting
* Neck stiffness (meningismus) — difficulty flexing chin to chest
* Visual disturbances — blurred vision in right eye, intermittent floaters
* Single episode of vomiting in the waiting room

!!! Neurological Assessment
* Alert and oriented to person, place, time, and situation
* Cranial nerves II-XII grossly intact
* No focal motor or sensory deficits
* Pupils equal, round, reactive to light (3mm bilaterally)
* No papilledema on fundoscopic exam (limited by photophobia)

!!! Medical History
* No history of migraines or recurrent headaches
* Oral contraceptive use — combined pill for 8 years
* Appendectomy at age 22
* No known drug allergies

!!! Family History
* Mother — cerebral aneurysm rupture at age 52, survived with surgical clipping
* Father — hypertension, type 2 diabetes
* Maternal aunt — stroke at age 60

!!! Current Medications
|!Medication |!Dose |!Frequency |
|Combined oral contraceptive |Levonorgestrel/Ethinyl estradiol |Once daily |
|Vitamin D3 |2000 IU |Once daily |
|Ibuprofen |400mg |As needed (last taken 3 days ago) |
EOF

chown ga:ga "$TIDDLER_DIR/Intake Form - Maria Santos.tid"
chown ga:ga "$TIDDLER_DIR/Intake Form - James Wilson.tid"
chown ga:ga "$TIDDLER_DIR/Intake Form - Aisha Patel.tid"

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count.txt
echo "Initial tiddler count: $INITIAL_COUNT"

# Restart TiddlyWiki to ensure new tiddlers are picked up
echo "Restarting TiddlyWiki server..."
pkill -f tiddlywiki 2>/dev/null || true
sleep 2
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for server to come up
for i in {1..15}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running"
        break
    fi
    sleep 1
done

# Verify intake forms are accessible
for PATIENT in "Maria Santos" "James Wilson" "Aisha Patel"; do
    if [ "$(tiddler_exists "Intake Form - $PATIENT")" = "true" ]; then
        echo "Verified: Intake Form - $PATIENT exists"
    else
        echo "WARNING: Intake Form - $PATIENT not found!"
    fi
done

# Focus Firefox and reload to show new tiddlers
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null
    DISPLAY=:1 xdotool key ctrl+r 2>/dev/null
    sleep 3
else
    DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key F5 2>/dev/null || true
    sleep 3
fi

take_screenshot /tmp/triage_initial.png

echo "=== Task setup complete ==="
