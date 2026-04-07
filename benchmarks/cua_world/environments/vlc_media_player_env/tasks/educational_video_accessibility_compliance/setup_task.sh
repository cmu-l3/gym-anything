#!/bin/bash
# Setup script for educational_video_accessibility_compliance task
# Creates a lecture video with 4 distinct sections and a transcript document
set -e

source /workspace/scripts/task_utils.sh

echo "Setting up educational_video_accessibility_compliance task..."

kill_vlc

# Create directories
mkdir -p /home/ga/Videos/accessible_output
mkdir -p /home/ga/Documents

# Section timestamps (each section ~22 seconds, total ~90 seconds)
# Section 1: 0-22s (Introduction)
# Section 2: 22-45s (Core Concepts)
# Section 3: 45-68s (Applications)
# Section 4: 68-90s (Summary)

# Build filter chain for lecture video with 4 colored sections and section titles
FILTER="drawbox=x=0:y=0:w=1920:h=1080:color=0x1a237e@0.3:t=fill:enable='between(t,0,22)'"
FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=0x1b5e20@0.3:t=fill:enable='between(t,22,45)'"
FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=0xb71c1c@0.3:t=fill:enable='between(t,45,68)'"
FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=0x4a148c@0.3:t=fill:enable='between(t,68,90)'"
FILTER="${FILTER},drawtext=text='Section 1 - Introduction to Data Science':x=(w-tw)/2:y=50:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=8:enable='between(t,0,22)'"
FILTER="${FILTER},drawtext=text='Section 2 - Core Statistical Concepts':x=(w-tw)/2:y=50:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=8:enable='between(t,22,45)'"
FILTER="${FILTER},drawtext=text='Section 3 - Real-World Applications':x=(w-tw)/2:y=50:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=8:enable='between(t,45,68)'"
FILTER="${FILTER},drawtext=text='Section 4 - Summary and Next Steps':x=(w-tw)/2:y=50:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=8:enable='between(t,68,90)'"
FILTER="${FILTER},drawtext=text='DS-301 Lecture 12':x=20:y=1040:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.4:boxborderw=4"

# Create lecture video (90 seconds, 1920x1080)
ffmpeg -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=25:duration=90" \
  -f lavfi -i "sine=frequency=300:sample_rate=44100:duration=90" \
  -vf "${FILTER}" \
  -c:v libx264 -preset ultrafast -b:v 4M \
  -c:a aac -b:a 128k -ac 2 -ar 44100 \
  /home/ga/Videos/lecture_recording.mp4 2>/dev/null

# Create transcript document with dialogue and section markers
cat > /home/ga/Documents/lecture_transcript.txt << 'TXEOF'
=== LECTURE TRANSCRIPT ===
Course: DS-301 Introduction to Data Science
Lecture 12: Statistical Foundations
Duration: ~90 seconds (condensed overview)

--- SECTION 1: Introduction to Data Science (0:00 - 0:22) ---

[0:01] Welcome to lecture twelve of DS-301.
[0:05] Today we will explore the statistical foundations that underpin modern data science.
[0:11] Understanding these concepts is crucial for any aspiring data scientist.
[0:17] Let us begin with an overview of the key topics we will cover.

--- SECTION 2: Core Statistical Concepts (0:22 - 0:45) ---

[0:23] The first fundamental concept is probability distributions.
[0:28] Normal distributions appear frequently in natural phenomena and measurement data.
[0:34] Hypothesis testing allows us to make rigorous decisions based on sample data.
[0:40] Confidence intervals quantify the uncertainty in our statistical estimates.

--- SECTION 3: Real-World Applications (0:45 - 1:08) ---

[0:46] In practice, these statistical tools drive critical business decisions.
[0:51] A/B testing relies on hypothesis testing to compare product variants.
[0:57] Regression analysis helps us model relationships between variables.
[1:03] Machine learning algorithms are built on these statistical foundations.

--- SECTION 4: Summary and Next Steps (1:08 - 1:30) ---

[1:09] To summarize, statistics provides the mathematical framework for data science.
[1:15] The key takeaways are: distributions model data, tests validate hypotheses.
[1:21] For next lecture, please review chapters eight and nine of the textbook.
[1:26] Thank you for attending. See you next week.

=== END OF TRANSCRIPT ===
TXEOF

# Create accessibility specification
cat > /home/ga/Documents/accessibility_spec.txt << 'ACCEOF'
=== ACCESSIBILITY COMPLIANCE REQUIREMENTS ===
Standard: Section 508 / WCAG 2.1 AA
Course: DS-301 Lecture 12

Required Deliverables (all saved to /home/ga/Videos/accessible_output/):

1. CLOSED CAPTIONS (SRT format)
   Filename: lecture_captions.srt
   Requirements:
   - Standard SRT format with sequential numbering
   - Timestamps must match the dialogue timing from the transcript
   - Each caption entry should correspond to one dialogue line
   - Minimum 16 caption entries covering all spoken content

2. HARDSUBBED VIDEO
   Filename: lecture_hardsubbed.mp4
   Requirements:
   - Captions permanently burned into video frames
   - No separate subtitle stream (captions are part of the video image)
   - Same duration as the original lecture video
   - Resolution: 1920x1080 (same as original)

3. LOW-BANDWIDTH VERSION
   Filename: lecture_lowband.mp4
   Requirements:
   - Resolution: 854x480 (or 640x480)
   - Reduced video bitrate (under 1.5 Mbps)
   - Must be significantly smaller file size than original
   - Audio preserved at reasonable quality

4. SECTION THUMBNAILS
   Filenames: section_1.png, section_2.png, section_3.png, section_4.png
   Requirements:
   - One thumbnail per section
   - Captured near the beginning of each section
   - Section title must be visible in the thumbnail
   - Minimum 640x360 resolution

5. DELIVERABLES MANIFEST
   Filename: manifest.json
   Requirements:
   - Valid JSON listing all deliverables
   - Each entry must include: filename, type, file_size_bytes, description
   - Must list all 4 categories of deliverables above
ACCEOF

# Store ground truth for verifier
cat > /tmp/.accessibility_ground_truth.json << 'GTEOF'
{
  "original_duration": 90,
  "original_width": 1920,
  "original_height": 1080,
  "sections": [
    {"number": 1, "start": 0, "end": 22, "title": "Introduction to Data Science"},
    {"number": 2, "start": 22, "end": 45, "title": "Core Statistical Concepts"},
    {"number": 3, "start": 45, "end": 68, "title": "Real-World Applications"},
    {"number": 4, "start": 68, "end": 90, "title": "Summary and Next Steps"}
  ],
  "caption_count_min": 16,
  "lowband_max_width": 854,
  "lowband_max_height": 480,
  "thumbnail_min_width": 640,
  "thumbnail_min_height": 360
}
GTEOF

chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Launch VLC with the lecture video (pre-position)
su - ga -c "DISPLAY=:1 vlc --no-video-title-show /home/ga/Videos/lecture_recording.mp4 &" 2>/dev/null || true
wait_for_window "VLC" 10

echo "Setup complete for educational_video_accessibility_compliance task"
