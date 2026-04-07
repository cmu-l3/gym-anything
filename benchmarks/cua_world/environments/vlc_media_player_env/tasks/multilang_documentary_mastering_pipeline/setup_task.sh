#!/bin/bash
echo "=== Setting up multilang_documentary_mastering_pipeline task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Kill any existing VLC
kill_vlc 2>/dev/null || pkill -f vlc 2>/dev/null || true

# Create required directories
mkdir -p /home/ga/Videos/source
mkdir -p /home/ga/Videos/mastered
mkdir -p /home/ga/Documents

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/Videos/mastered/documentary_master.mkv
rm -f /home/ga/Videos/mastered/dist_english.mp4
rm -f /home/ga/Videos/mastered/dist_spanish.mp4
rm -f /home/ga/Videos/mastered/dist_audio.m4a
rm -f /home/ga/Videos/mastered/qa_proof_sheet.png
rm -f /home/ga/Documents/mastering_report.json
rm -f /tmp/task_result.json

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# ============================================================
# Ground Truth Variables (hidden from agent — used for generation only)
# ============================================================
VIDEO_FLASH_START=5.0
VIDEO_FLASH_END=5.5
EN_BEEP_TIME=8.5
ES_BEEP_TIME=6.8
ME_BEEP_TIME=5.0
TOTAL_DURATION=90

# ============================================================
# Generate Source Media Files
# ============================================================

echo "Generating main_video.mov (90s, 1920x1080, 30fps, flash at ${VIDEO_FLASH_START}s)..."
ffmpeg -y \
  -f lavfi -i "testsrc2=duration=${TOTAL_DURATION}:size=1920x1080:rate=30" \
  -f lavfi -i "anoisesrc=duration=${TOTAL_DURATION}:color=pink:amplitude=0.01:sample_rate=48000" \
  -vf "drawtext=text='%{pts\:hms}':fontsize=36:fontcolor=white:x=10:y=10:box=1:boxcolor=black@0.4:boxborderw=5,\
drawtext=text='AMAZON DOCUMENTARY - RAW FOOTAGE':fontsize=20:fontcolor=gray:x=10:y=60,\
drawbox=enable='between(t,${VIDEO_FLASH_START},${VIDEO_FLASH_END})':x=0:y=0:w=iw:h=ih:color=white:t=fill" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -c:a aac -b:a 64k \
  /home/ga/Videos/source/main_video.mov 2>/dev/null

# Pre-beep duration, beep duration, post-beep duration must sum to TOTAL_DURATION
BEEP_DUR=0.5

echo "Generating narration_en.wav (beep at ${EN_BEEP_TIME}s)..."
EN_POST=$(echo "${TOTAL_DURATION} - ${EN_BEEP_TIME} - ${BEEP_DUR}" | bc)
ffmpeg -y \
  -f lavfi -i "anoisesrc=duration=${EN_BEEP_TIME}:color=brown:amplitude=0.01:sample_rate=48000" \
  -f lavfi -i "sine=frequency=1000:duration=${BEEP_DUR}:sample_rate=48000" \
  -f lavfi -i "anoisesrc=duration=${EN_POST}:color=brown:amplitude=0.01:sample_rate=48000" \
  -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1[out]" \
  -map "[out]" -c:a pcm_s16le -ar 48000 -ac 1 \
  /home/ga/Videos/source/narration_en.wav 2>/dev/null

echo "Generating narration_es.wav (beep at ${ES_BEEP_TIME}s)..."
ES_POST=$(echo "${TOTAL_DURATION} - ${ES_BEEP_TIME} - ${BEEP_DUR}" | bc)
ffmpeg -y \
  -f lavfi -i "anoisesrc=duration=${ES_BEEP_TIME}:color=brown:amplitude=0.01:sample_rate=48000" \
  -f lavfi -i "sine=frequency=1000:duration=${BEEP_DUR}:sample_rate=48000" \
  -f lavfi -i "anoisesrc=duration=${ES_POST}:color=brown:amplitude=0.01:sample_rate=48000" \
  -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1[out]" \
  -map "[out]" -c:a pcm_s16le -ar 48000 -ac 1 \
  /home/ga/Videos/source/narration_es.wav 2>/dev/null

echo "Generating music_effects.wav (stereo, beep at ${ME_BEEP_TIME}s)..."
ME_POST=$(echo "${TOTAL_DURATION} - ${ME_BEEP_TIME} - ${BEEP_DUR}" | bc)
ffmpeg -y \
  -f lavfi -i "sine=frequency=261.63:duration=${ME_BEEP_TIME}:sample_rate=48000" \
  -f lavfi -i "sine=frequency=1000:duration=${BEEP_DUR}:sample_rate=48000" \
  -f lavfi -i "sine=frequency=261.63:duration=${ME_POST}:sample_rate=48000" \
  -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1[out]" \
  -map "[out]" -c:a pcm_s16le -ar 48000 -ac 2 \
  /home/ga/Videos/source/music_effects.wav 2>/dev/null

# ============================================================
# Generate Subtitle Files (with known timing errors)
# ============================================================

echo "Creating subtitle files..."

# English subtitles — all timestamps are 2.5 seconds TOO EARLY
# Correct first cue should start at 12.500s (shown here as 10.000s)
cat > /home/ga/Videos/source/subs_en.srt << 'SRTEOF'
1
00:00:10,000 --> 00:00:14,500
In the heart of the Amazon rainforest,
researchers made a startling discovery.

2
00:00:22,500 --> 00:00:27,000
A previously unknown species of orchid
was found growing on ancient ceiba trees.

3
00:00:35,000 --> 00:00:39,500
The three-month expedition was funded
by the National Science Foundation.

4
00:00:47,500 --> 00:00:52,000
Lead botanist Dr. Elena Vasquez called it
"the find of a lifetime."

5
00:00:57,500 --> 00:01:02,000
The team's findings were published
in the journal Nature Ecology.

6
00:01:10,000 --> 00:01:14,500
This discovery has reshaped our understanding
of tropical biodiversity.
SRTEOF

# Spanish subtitles — all timestamps are 4.0 seconds TOO EARLY
# Correct first cue should start at 12.500s (shown here as 8.500s)
cat > /home/ga/Videos/source/subs_es.srt << 'SRTEOF'
1
00:00:08,500 --> 00:00:13,000
En el corazon de la selva amazonica,
los investigadores hicieron un hallazgo sorprendente.

2
00:00:21,000 --> 00:00:25,500
Una especie de orquidea previamente desconocida
fue encontrada en antiguos arboles de ceiba.

3
00:00:33,500 --> 00:00:38,000
La expedicion de tres meses fue financiada
por la Fundacion Nacional de Ciencias.

4
00:00:46,000 --> 00:00:50,500
La botanica principal, Dra. Elena Vasquez,
lo llamo "el hallazgo de su vida."

5
00:00:56,000 --> 00:01:00,500
Los hallazgos del equipo fueron publicados
en la revista Nature Ecology.

6
00:01:08,500 --> 00:01:13,000
Este descubrimiento ha cambiado nuestra comprension
de la biodiversidad tropical.
SRTEOF

# ============================================================
# Create Synchronization Notes Document
# ============================================================

cat > /home/ga/Documents/sync_notes.txt << 'NOTESEOF'
=== AUDIO-VIDEO SYNCHRONIZATION NOTES ===
Project: Amazon Documentary — Post-Production Phase

All source recordings contain a synchronization reference marker
embedded in the first 10 seconds of each file:

  VIDEO:  A half-second WHITE FLASH frame (full-screen white)
  AUDIO:  A half-second 1000 Hz TONE BURST at high amplitude

The Music & Effects track (music_effects.wav) was recorded in-sync
with the video — its tone burst coincides with the video flash.
Use it as a reference to verify your offset calculations.

The narration tracks were recorded in separate sessions and are
NOT time-aligned with the video. To synchronize them:

  1. Find the exact timestamp of the white flash in main_video.mov
     (use frame analysis, scene detection, or brightness analysis)

  2. Find the exact timestamp of the 1kHz tone burst in each
     narration audio file (analyze amplitude peaks or use
     spectral analysis — the burst is much louder than the
     surrounding background audio)

  3. Calculate offset: (audio_beep_time - video_flash_time)
     This is how many seconds LATE the audio is.

  4. Apply the NEGATIVE of this offset when muxing to pull
     the audio track earlier into alignment.

SUBTITLE TIMING:
  English subtitles: 2.5 seconds EARLY — shift all timestamps +2.5s
  Spanish subtitles: 4.0 seconds EARLY — shift all timestamps +4.0s

See delivery_spec.json for complete output format requirements.
NOTESEOF

# ============================================================
# Create Delivery Specification Document
# ============================================================

cat > /home/ga/Documents/delivery_spec.json << 'SPECEOF'
{
  "project": "AMAZON-DOC-2024",
  "source_directory": "/home/ga/Videos/source",
  "output_directory": "/home/ga/Videos/mastered",
  "source_files": {
    "video": "main_video.mov",
    "narration_english": "narration_en.wav",
    "narration_spanish": "narration_es.wav",
    "music_effects": "music_effects.wav",
    "subtitles_english": "subs_en.srt",
    "subtitles_spanish": "subs_es.srt"
  },
  "deliverables": {
    "master": {
      "filename": "documentary_master.mkv",
      "container": "matroska",
      "video": {
        "codec": "h264",
        "resolution": "1920x1080",
        "frame_rate": 30
      },
      "audio_tracks": [
        {"index": 0, "source": "narration_en.wav", "language_tag": "eng", "label": "English Narration"},
        {"index": 1, "source": "narration_es.wav", "language_tag": "spa", "label": "Spanish Narration"},
        {"index": 2, "source": "music_effects.wav", "language_tag": "und", "label": "Music and Effects"}
      ],
      "subtitle_tracks": [
        {"index": 0, "source": "subs_en.srt", "language_tag": "eng", "default": true},
        {"index": 1, "source": "subs_es.srt", "language_tag": "spa", "default": false}
      ],
      "notes": "All audio tracks must be time-aligned using detected sync offsets. Subtitles must have timing corrections applied before embedding. Discard the scratch audio from main_video.mov."
    },
    "dist_english": {
      "filename": "dist_english.mp4",
      "container": "mp4",
      "video": {
        "codec": "h264",
        "resolution": "1280x720"
      },
      "audio": {
        "codec": "aac",
        "channels": 2,
        "description": "English narration mixed with M&E as a single stereo track"
      },
      "subtitles": {
        "method": "hardburn",
        "source": "subs_en.srt (timing-corrected)",
        "note": "No subtitle stream in output — text must be burned into video frames"
      }
    },
    "dist_spanish": {
      "filename": "dist_spanish.mp4",
      "container": "mp4",
      "video": {
        "codec": "h264",
        "resolution": "1280x720"
      },
      "audio": {
        "codec": "aac",
        "channels": 2,
        "description": "Spanish narration mixed with M&E as a single stereo track"
      },
      "subtitles": {
        "method": "hardburn",
        "source": "subs_es.srt (timing-corrected)",
        "note": "No subtitle stream in output — text must be burned into video frames"
      }
    },
    "dist_audio": {
      "filename": "dist_audio.m4a",
      "container": "m4a",
      "video": null,
      "audio": {
        "codec": "aac",
        "channels": 2,
        "bitrate_kbps": 256,
        "description": "English narration mixed with M&E, no video"
      }
    },
    "proof_sheet": {
      "filename": "qa_proof_sheet.png",
      "type": "image",
      "layout": "3x2 grid",
      "thumbnail_size": "320x180",
      "timestamps_seconds": [15, 30, 45, 60, 75, 90],
      "source": "documentary_master.mkv",
      "expected_dimensions": "960x360"
    },
    "report": {
      "filename": "mastering_report.json",
      "location": "/home/ga/Documents/mastering_report.json",
      "required_sections": {
        "sync_analysis": {
          "video_flash_timestamp_sec": "detected timestamp of white flash",
          "narration_en_beep_timestamp_sec": "detected timestamp of EN beep",
          "narration_es_beep_timestamp_sec": "detected timestamp of ES beep",
          "applied_offset_en_sec": "offset applied to EN narration",
          "applied_offset_es_sec": "offset applied to ES narration"
        },
        "subtitle_corrections": {
          "english_shift_sec": "shift applied to EN subtitles",
          "spanish_shift_sec": "shift applied to ES subtitles"
        },
        "deliverables": "array of objects with filename, video_codec, audio_codec, resolution, duration_sec, audio_tracks, subtitle_tracks for each output file"
      }
    }
  }
}
SPECEOF

# ============================================================
# Set Permissions
# ============================================================

chown -R ga:ga /home/ga/Videos /home/ga/Documents

# ============================================================
# Launch VLC
# ============================================================

echo "Launching VLC Media Player..."
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true

# Wait for VLC window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "vlc"; then
        break
    fi
    sleep 0.5
done

# Maximize and focus VLC
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Give UI time to stabilize
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete for multilang_documentary_mastering_pipeline ==="
