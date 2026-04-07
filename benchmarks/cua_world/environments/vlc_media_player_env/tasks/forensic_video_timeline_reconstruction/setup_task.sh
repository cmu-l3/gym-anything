#!/bin/bash
# Setup script for forensic_video_timeline_reconstruction task
# Creates a 3-minute dashcam video with 5 visual event markers at known timestamps
# and an INCORRECT incident log the agent must correct
set -e

source /workspace/scripts/task_utils.sh

echo "Setting up forensic_video_timeline_reconstruction task..."

kill_vlc

# Create directories
mkdir -p /home/ga/Videos/evidence_clips
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Pictures/forensic_snapshots

# Ground truth event timestamps (seconds into video)
EVT_A=15
EVT_B=42
EVT_C=78
EVT_D=121
EVT_E=156

# Build ffmpeg filter chain for dashcam video with event markers
# Each event is a 2-second colored bar at the bottom with label text
FILTER="drawtext=text='DASHCAM-01  %{pts\:hms}':x=10:y=10:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=5"
FILTER="${FILTER},drawbox=x=0:y=680:w=1280:h=40:color=red@0.9:t=fill:enable='between(t,${EVT_A},${EVT_A}+2)'"
FILTER="${FILTER},drawtext=text='EVENT-A  IMPACT':x=420:y=688:fontsize=22:fontcolor=white:enable='between(t,${EVT_A},${EVT_A}+2)'"
FILTER="${FILTER},drawbox=x=0:y=680:w=1280:h=40:color=green@0.9:t=fill:enable='between(t,${EVT_B},${EVT_B}+2)'"
FILTER="${FILTER},drawtext=text='EVENT-B  SWERVE':x=420:y=688:fontsize=22:fontcolor=white:enable='between(t,${EVT_B},${EVT_B}+2)'"
FILTER="${FILTER},drawbox=x=0:y=680:w=1280:h=40:color=blue@0.9:t=fill:enable='between(t,${EVT_C},${EVT_C}+2)'"
FILTER="${FILTER},drawtext=text='EVENT-C  DEBRIS':x=420:y=688:fontsize=22:fontcolor=white:enable='between(t,${EVT_C},${EVT_C}+2)'"
FILTER="${FILTER},drawbox=x=0:y=680:w=1280:h=40:color=yellow@0.9:t=fill:enable='between(t,${EVT_D},${EVT_D}+2)'"
FILTER="${FILTER},drawtext=text='EVENT-D  STOP':x=430:y=688:fontsize=22:fontcolor=black:enable='between(t,${EVT_D},${EVT_D}+2)'"
FILTER="${FILTER},drawbox=x=0:y=680:w=1280:h=40:color=white@0.9:t=fill:enable='between(t,${EVT_E},${EVT_E}+2)'"
FILTER="${FILTER},drawtext=text='EVENT-E  REVERSE':x=410:y=688:fontsize=22:fontcolor=black:enable='between(t,${EVT_E},${EVT_E}+2)'"

# Create dashcam-style video (3 min, 1280x720, with moving test pattern)
ffmpeg -y \
  -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=180" \
  -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=180" \
  -vf "${FILTER}" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k \
  /home/ga/Videos/dashcam_footage.mp4 2>/dev/null

# Create INCORRECT incident log (timestamps off by 5-10 seconds)
# These wrong timestamps serve as the wrong-target gate
cat > /home/ga/Documents/incident_log.txt << 'LOGEOF'
=== INCIDENT LOG - Preliminary Report ===
Case #: INS-2026-03847
Date of Incident: 2026-03-06
Dashcam File: dashcam_footage.mp4 (3 minutes)

Reported Events (approximate timestamps from witness statements):
-----------------------------------------------------------------
Event A - Initial Impact
  Approximate time: 0:00:22 (22 seconds)
  Description: First contact between vehicles

Event B - Evasive Maneuver
  Approximate time: 0:00:35 (35 seconds)
  Description: Second vehicle swerves

Event C - Road Debris
  Approximate time: 0:01:25 (85 seconds)
  Description: Debris scattered across roadway

Event D - Emergency Stop
  Approximate time: 0:01:54 (114 seconds)
  Description: Vehicle comes to emergency stop

Event E - Reverse Movement
  Approximate time: 0:02:43 (163 seconds)
  Description: Vehicle reverses from scene

NOTE: Witness timestamps may be inaccurate. Please verify all
timestamps against the actual dashcam footage and produce a
corrected forensic timeline.

Required Deliverables:
1. Forensic snapshot of each event
2. Corrected timeline (JSON format) at /home/ga/Documents/corrected_timeline.json
3. 5-second evidence clips centered on each event at /home/ga/Videos/evidence_clips/
LOGEOF

# Store ground truth for verifier (hidden from agent)
cat > /tmp/.forensic_ground_truth.json << 'GTEOF'
{
  "events": {
    "A": {"timestamp": 15, "label": "IMPACT", "color": "red"},
    "B": {"timestamp": 42, "label": "SWERVE", "color": "green"},
    "C": {"timestamp": 78, "label": "DEBRIS", "color": "blue"},
    "D": {"timestamp": 121, "label": "STOP", "color": "yellow"},
    "E": {"timestamp": 156, "label": "REVERSE", "color": "white"}
  },
  "wrong_timestamps": {
    "A": 22,
    "B": 35,
    "C": 85,
    "D": 114,
    "E": 163
  },
  "tolerance_sec": 2,
  "clip_duration_sec": 5
}
GTEOF

chown -R ga:ga /home/ga/Videos /home/ga/Documents /home/ga/Pictures/forensic_snapshots

# Launch VLC with the dashcam footage (pre-position)
su - ga -c "DISPLAY=:1 vlc --no-video-title-show /home/ga/Videos/dashcam_footage.mp4 &" 2>/dev/null || true
wait_for_window "VLC" 10

echo "Setup complete for forensic_video_timeline_reconstruction task"
