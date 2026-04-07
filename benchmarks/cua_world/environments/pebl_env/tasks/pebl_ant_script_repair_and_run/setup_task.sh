#!/bin/bash
# Setup for pebl_ant_script_repair_and_run task
# Creates a broken ANT PEBL script with 4 domain-knowledge bugs
# that the agent must identify and fix using knowledge of Fan et al. (2002)

set -e
echo "=== Setting up pebl_ant_script_repair_and_run task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create task directories
mkdir -p /home/ga/pebl/tasks/ant
mkdir -p /home/ga/pebl/data/ant
chown -R ga:ga /home/ga/pebl

# Write the broken ANT PEBL script with 4 injected bugs:
#   Bug 1: gSOA = 4000 (correct: 400 ms)
#   Bug 2: gCueTypes missing "double_cue" (correct: 4 cue types)
#   Bug 3: gFlankerTypes missing "neutral" (correct: 3 flanker types)
#   Bug 4: gTestBlocks = 1 (correct: 3 blocks)
cat > /home/ga/pebl/tasks/ant/ant_task.pbl << 'PBLEOF'
## Attention Network Test (ANT)
## Adapted from Fan, McCandliss, Sommer, Raz & Posner (2002)
## J Cogn Neurosci, 14(3):340-347
##
## Standard ANT protocol:
##   - 4 cue conditions x 3 flanker conditions x 2 target directions
##   - Cue-to-target SOA: 400 ms
##   - 3 test blocks (plus 1 practice block)
##
## NOTE: This script requires debugging before use. See lab notebook.

define gSubjectID { "test" }
define gSessionNum { 1 }

## ---- PARAMETER SECTION (CHECK THESE CAREFULLY) ----
## Bug here: SOA value is wrong
define gSOA { 4000 }          ## Cue-to-target stimulus onset asynchrony (ms)
define gCueDuration { 100 }   ## Duration of cue display (ms)
define gTargetDuration { 1700 }  ## Max target display time (ms)
define gFixDuration { 400 }   ## Post-target fixation (ms)
define gITI { 3500 }          ## Inter-trial interval (ms)
define gPracTrials { 24 }     ## Number of practice trials

## Bug here: missing one cue type
define gCueTypes { ["no_cue","center_cue","spatial_cue"] }

## Bug here: missing one flanker type
define gFlankerTypes { ["congruent","incongruent"] }

## Bug here: wrong number of test blocks
define gTestBlocks { 1 }

define gTargetDirections { ["left","right"] }
define gTrialsPerBlock { 48 }
define gDataFile { FileOpenWrite(Concatenate("~/pebl/data/ant/ant_",gSubjectID,"_s",gSessionNum,".csv")) }

## ---- HELPER FUNCTIONS ----

define DrawFixation(win)
{
    DrawLine(win, 630, 360, 650, 360, MakeColor("black"))
    DrawLine(win, 640, 350, 640, 370, MakeColor("black"))
    UpdateDisplay()
}

define DrawCue(win, cueType, targetSide)
{
    DrawFixation(win)
    if(cueType == "center_cue")
    {
        FilledEllipse(win, 635, 355, 10, 10, MakeColor("black"))
    } elseif(cueType == "double_cue")
    {
        FilledEllipse(win, 635, 315, 10, 10, MakeColor("black"))
        FilledEllipse(win, 635, 395, 10, 10, MakeColor("black"))
    } elseif(cueType == "spatial_cue")
    {
        if(targetSide == "up")
        {
            FilledEllipse(win, 635, 315, 10, 10, MakeColor("black"))
        } else {
            FilledEllipse(win, 635, 395, 10, 10, MakeColor("black"))
        }
    }
    UpdateDisplay()
}

define DrawFlankers(win, flankerType, targetDir)
{
    ## Draw central target arrow
    if(targetDir == "right")
    {
        DrawText(win, ">>>>>>", 580, 360, MakeColor("black"), "Arial", 24)
    } else {
        DrawText(win, "<<<<<<", 580, 360, MakeColor("black"), "Arial", 24)
    }
    ## For congruent: flankers same direction as target
    ## For incongruent: flankers opposite direction
    ## For neutral: flankers are dashes (no directional conflict)
    UpdateDisplay()
}

define WriteDataHeader()
{
    FilePrint(gDataFile, "subject,session,block,trial,cue_type,flanker_type,target_dir,rt_ms,correct,response")
}

## ---- MAIN PROGRAM ----

define Start(lArgs)
{
    gSubjectID <- GetArg(lArgs, 1)
    gSessionNum <- GetArg(lArgs, 2)

    win <- MakeWindow("black")

    ## Open data file and write header
    WriteDataHeader()

    ## Instructions
    DrawText(win, "Attention Network Test", 400, 200, MakeColor("white"), "Arial", 28)
    DrawText(win, "Press Z for LEFT arrow, / for RIGHT arrow", 400, 280, MakeColor("white"), "Arial", 18)
    DrawText(win, "Respond as fast and accurately as possible", 400, 320, MakeColor("white"), "Arial", 18)
    DrawText(win, "Press SPACE to begin practice", 400, 420, MakeColor("white"), "Arial", 18)
    UpdateDisplay()
    WaitForKeyPress(" ")

    ## Practice block
    DrawText(win, "PRACTICE BLOCK", 400, 300, MakeColor("white"), "Arial", 28)
    DrawText(win, "Press SPACE to start", 400, 380, MakeColor("white"), "Arial", 18)
    UpdateDisplay()
    WaitForKeyPress(" ")

    block <- 1
    trial <- 1
    loop(trial, 1, gPracTrials)
    {
        cue <- RandomDiscrete(Length(gCueTypes))
        flank <- RandomDiscrete(Length(gFlankerTypes))
        dir <- RandomDiscrete(Length(gTargetDirections))

        cueType <- Nth(gCueTypes, cue)
        flankerType <- Nth(gFlankerTypes, flank)
        targetDir <- Nth(gTargetDirections, dir)

        ## Fixation
        DrawFixation(win)
        Wait(gFixDuration)

        ## Cue
        DrawCue(win, cueType, targetDir)
        Wait(gCueDuration)

        ## SOA gap (fixation between cue offset and target onset)
        DrawFixation(win)
        Wait(gSOA)

        ## Target + flankers
        DrawFlankers(win, flankerType, targetDir)
        t0 <- GetTime()
        resp <- WaitForKeyPress("z/", gTargetDuration)
        rt <- GetTime() - t0

        correct <- 0
        if((targetDir == "left" and resp == "z") or (targetDir == "right" and resp == "/"))
        {
            correct <- 1
        }

        FilePrint(gDataFile, Concatenate(gSubjectID, ",", gSessionNum, ",practice,", trial, ",",
                  cueType, ",", flankerType, ",", targetDir, ",", rt, ",", correct, ",", resp))

        DrawFixation(win)
        Wait(gITI)
        trial <- trial + 1
    }

    ## Test blocks
    DrawText(win, "Practice complete. Beginning test blocks.", 400, 280, MakeColor("white"), "Arial", 18)
    DrawText(win, "Press SPACE to continue", 400, 360, MakeColor("white"), "Arial", 18)
    UpdateDisplay()
    WaitForKeyPress(" ")

    block <- 1
    loop(block, 1, gTestBlocks)
    {
        DrawText(win, Concatenate("Block ", block, " of ", gTestBlocks), 400, 300, MakeColor("white"), "Arial", 24)
        DrawText(win, "Press SPACE to start", 400, 380, MakeColor("white"), "Arial", 18)
        UpdateDisplay()
        WaitForKeyPress(" ")

        trial <- 1
        loop(trial, 1, gTrialsPerBlock)
        {
            cue <- RandomDiscrete(Length(gCueTypes))
            flank <- RandomDiscrete(Length(gFlankerTypes))
            dir <- RandomDiscrete(Length(gTargetDirections))

            cueType <- Nth(gCueTypes, cue)
            flankerType <- Nth(gFlankerTypes, flank)
            targetDir <- Nth(gTargetDirections, dir)

            DrawFixation(win)
            Wait(gFixDuration)
            DrawCue(win, cueType, targetDir)
            Wait(gCueDuration)
            DrawFixation(win)
            Wait(gSOA)
            DrawFlankers(win, flankerType, targetDir)
            t0 <- GetTime()
            resp <- WaitForKeyPress("z/", gTargetDuration)
            rt <- GetTime() - t0

            correct <- 0
            if((targetDir == "left" and resp == "z") or (targetDir == "right" and resp == "/"))
            {
                correct <- 1
            }

            FilePrint(gDataFile, Concatenate(gSubjectID, ",", gSessionNum, ",", block, ",", trial, ",",
                      cueType, ",", flankerType, ",", targetDir, ",", rt, ",", correct, ",", resp))

            DrawFixation(win)
            Wait(gITI)
            trial <- trial + 1
        }
        block <- block + 1
    }

    ## End of task
    FileClose(gDataFile)
    DrawText(win, "Task complete. Thank you!", 400, 300, MakeColor("white"), "Arial", 24)
    DrawText(win, "Press SPACE to exit", 400, 380, MakeColor("white"), "Arial", 18)
    UpdateDisplay()
    WaitForKeyPress(" ")
}
PBLEOF

chown -R ga:ga /home/ga/pebl/tasks
chmod 644 /home/ga/pebl/tasks/ant/ant_task.pbl
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open gedit with the broken script for the agent to inspect
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gedit /home/ga/pebl/tasks/ant/ant_task.pbl &" 2>/dev/null || true

# Also open a terminal
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c '
echo \"=== ANT Script Repair Task ===\"
echo \"\"
echo \"Broken script: ~/pebl/tasks/ant/ant_task.pbl\"
echo \"Run with:      run-pebl ~/pebl/tasks/ant/ant_task.pbl\"
echo \"Bug report:    ~/pebl/tasks/ant/bug_report.txt\"
echo \"\"
echo \"The script has bugs that violate the standard ANT protocol (Fan et al. 2002).\"
echo \"Find and fix all bugs, run the fixed task, then document bugs in bug_report.txt\"
echo \"\"
bash' > /tmp/ant_terminal.log 2>&1 &"

# Wait for windows to appear
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== pebl_ant_script_repair_and_run setup complete ==="
echo "Broken script: /home/ga/pebl/tasks/ant/ant_task.pbl (4 bugs injected)"
echo "Bug 1: gSOA = 4000 (correct: 400)"
echo "Bug 2: gCueTypes missing 'double_cue'"
echo "Bug 3: gFlankerTypes missing 'neutral'"
echo "Bug 4: gTestBlocks = 1 (correct: 3)"
