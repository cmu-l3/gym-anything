#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Foster Behavioral Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw notes file with realistic scattered observations
RAW_NOTES_PATH="$WORKSPACE_DIR/jamie_raw_notes.txt"

cat > "$RAW_NOTES_PATH" << 'EOF'
JAMIE'S BEHAVIORAL NOTES - 3 MONTH REVIEW
==========================================

Sept 15 - Big meltdown at breakfast when toast burnt. Threw plate across kitchen, yelling for 20 mins straight. Couldn't talk to him at all. Used calm corner strategy but took a while. Finally worked after 45 mins total. Very exhausted after.

Sept 18 - GOOD DAY! Asked for help with homework without prompting! First time ever! We worked together on math for 15 mins, no issues at all. He seemed proud of himself.

Sept 22 - School called - got in fight at recess. Sounds like another kid took his ball and he pushed back hard. Teacher had to intervene. Took 2 hours to calm down at home when I picked him up. Lots of pacing and muttering.

Sept 25 - Bedtime transition very rough. 10 minute warning didn't help at all. Screaming about not being tired. Tried sensory brush technique - didn't work. Finally calmed around 10pm.

Sept 29 - Amazing morning routine! Got dressed without any reminders. Made his bed. Even smiled at breakfast and said "thank you" for pancakes. Days like this make it all worth it.

Oct 3 - Transition to bedtime hard again. The visual warning timer didn't help much. Tried the sensory brush approach again - THIS time it worked much better. Down in 30 mins.

Oct 8 - Tantrum when I said no more candy after dinner. Started yelling and stomping. BUT less intense than last month's incidents. He didn't throw anything! Calmed down in about 25 mins with deep breathing prompts from me.

Oct 12 - School pickup - teacher gave positive report! Said he shared crayons with new kid. Small thing but HUGE for Jamie.

Oct 15 - MILESTONE! He initiated a hug when I got home from store! Just came up and hugged me. Almost cried. Very proud of him building trust.

Oct 20 - Another good school report. Teacher said he raised hand to answer question and shared toy with classmate during free time. Making progress with peer relationships.

Oct 24 - Evening was challenging. Seemed really tired and overwhelmed. Shut down, wouldn't talk. Got out the weighted blanket without asking - he accepted it and that helped a lot. Calmed in 20 mins.

Oct 27 - Rough bedtime. But used weighted blanket again and it worked. Getting better at recognizing what helps him.

Nov 2 - Smooth morning AND smooth bedtime! Used the visual schedule we made together. He checked off each task himself. Only took 10 mins to settle for bed. PROGRESS!

Nov 5 - Asked to use the calm corner himself when he felt frustrated about video game. Didn't even have a meltdown - just went there on his own! 15 mins later came out calm. This is self-regulation!!

Nov 10 - Small upset about screen time limits. I reminded him about breathing exercises and he USED them without me prompting more. Recovered in just 5 mins. Huge difference from September.

Nov 14 - School field trip to museum - teacher reported he did GREAT. No incidents entire day. Stayed with group, followed instructions, even helped another kid who dropped their lunch.

Nov 18 - Evening struggle with homework frustration but he caught himself getting upset and asked for a break. We did breathing together. Came back to homework 10 mins later and finished it. SELF AWARENESS!

Nov 22 - He's now asking for his calming tools HIMSELF. This morning asked for sensory brush before school because he "felt wiggly". Using coping strategies without any prompting from me. Ready to present this progress at review meeting!

INTERVENTIONS THAT SEEM TO WORK:
- Calm corner (hit or miss at first, better now)
- Sensory brush (works better lately)
- Weighted blanket (very effective)
- Visual schedules (game changer!)
- Deep breathing exercises (he's learning these!)

TRIGGERS I'VE NOTICED:
- Transitions (bedtime especially hard)
- Being told "no" 
- Unexpected changes
- Sensory overload (loud noises, too much stimulation)
- Fatigue

OVERALL: Seeing real progress. De-escalation times way down. Self-regulation starting to emerge. Peer relationships improving. Ready for 90-day review.
EOF

chown ga:ga "$RAW_NOTES_PATH"

echo "✅ Raw notes file created at: $RAW_NOTES_PATH"

# Create a blank document to start from (optional - agent could create new doc)
# We'll let the agent create the document themselves for this task
# This makes it more realistic and tests document creation

echo "📝 Raw notes file ready for review"
echo "📄 File location: $RAW_NOTES_PATH"

# Display the notes file in a text editor so agent can see it
# Launch gedit or similar to display the raw notes
echo "Opening raw notes file for reference..."
su - ga -c "DISPLAY=:1 gedit '$RAW_NOTES_PATH' > /tmp/gedit_notes.log 2>&1 &"

sleep 2

# Now launch ONLYOFFICE to create the new document
# We'll launch with a new blank document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors > /tmp/onlyoffice_foster_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_foster_task.log || true
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

echo "=== Foster Behavioral Log Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "══════════════════════════════════════════════════════════"
echo "You are a therapeutic foster parent preparing for a critical"
echo "90-day placement review meeting tomorrow morning."
echo ""
echo "INPUT FILE: /home/ga/Documents/TextDocuments/jamie_raw_notes.txt"
echo "  (Currently open in text editor for reference)"
echo ""
echo "YOUR TASK: Create a professional document that transforms these"
echo "scattered notes into a structured behavioral tracking report."
echo ""
echo "REQUIRED OUTPUT: /home/ga/Documents/TextDocuments/jamie_placement_review.docx"
echo ""
echo "DOCUMENT MUST INCLUDE:"
echo "  1. Professional header with title and date range (Sept 15 - Nov 22, 2024)"
echo "  2. Summary statistics (total incidents, average de-escalation time, etc.)"
echo "  3. Behavioral incident log TABLE with columns:"
echo "     - Date"
echo "     - Trigger/Context"
echo "     - Behavior Description"
echo "     - Intervention Used"
echo "     - Resolution Time"
echo "  4. Progress indicators section showing measurable improvements"
echo "  5. Intervention effectiveness analysis"
echo ""
echo "EXTRACT DATA FROM RAW NOTES:"
echo "  - Identify incidents with dates (Sept 15, Oct 8, Nov 10, etc.)"
echo "  - Note intervention strategies (calm corner, sensory brush, weighted blanket, etc.)"
echo "  - Calculate/observe improvement (45 mins → 5 mins recovery time)"
echo "  - Identify self-regulation milestones (Nov 5, Nov 22)"
echo ""
echo "SAVE TO: /home/ga/Documents/TextDocuments/jamie_placement_review.docx"
echo "══════════════════════════════════════════════════════════"