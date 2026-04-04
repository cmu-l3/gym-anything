#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Extract Embedded Subtitles Task ==="

kill_vlc ga
sleep 1

# Ensure subtitle directory exists
mkdir -p /home/ga/Videos/subtitles
chown ga:ga /home/ga/Videos/subtitles

# Create sample subtitle files for embedding
echo "Creating sample subtitle tracks..."

# English subtitle (the one to be extracted)
cat > /tmp/english_sub.srt <<'EOF'
1
00:00:01,000 --> 00:00:04,000
Hello, this is a sample video.

2
00:00:04,500 --> 00:00:08,000
It demonstrates subtitle extraction.

3
00:00:08,500 --> 00:00:12,000
You need to extract the English track.

4
00:00:12,500 --> 00:00:16,000
This video contains multiple subtitle streams.

5
00:00:16,500 --> 00:00:20,000
English, Spanish, and French subtitles are embedded.

6
00:00:20,500 --> 00:00:24,000
Your task is to save the English subtitles.

7
00:00:24,500 --> 00:00:28,000
The output should be a standalone SRT file.

8
00:00:28,500 --> 00:00:32,000
Use VLC's conversion functionality.

9
00:00:32,500 --> 00:00:36,000
Navigate to Media, then Convert/Save.

10
00:00:36,500 --> 00:00:40,000
Select the video and extract subtitles.

11
00:00:40,500 --> 00:00:44,000
Save to the subtitles directory.

12
00:00:44,500 --> 00:00:48,000
Good luck with the extraction!

13
00:00:48,500 --> 00:00:52,000
This task tests your stream manipulation skills.

14
00:00:52,500 --> 00:00:56,000
Understanding container formats is important.

15
00:00:56,500 --> 00:01:00,000
MKV files can contain many streams.
EOF

# Spanish subtitle (distractor)
cat > /tmp/spanish_sub.srt <<'EOF'
1
00:00:01,000 --> 00:00:04,000
Hola, este es un video de muestra.

2
00:00:04,500 --> 00:00:08,000
Demuestra la extracción de subtítulos.

3
00:00:08,500 --> 00:00:12,000
Necesitas extraer la pista en inglés.

4
00:00:12,500 --> 00:00:16,000
Este video contiene múltiples flujos de subtítulos.

5
00:00:16,500 --> 00:00:20,000
Los subtítulos en inglés, español y francés están incrustados.

6
00:00:20,500 --> 00:00:24,000
Tu tarea es guardar los subtítulos en inglés.

7
00:00:24,500 --> 00:00:28,000
La salida debe ser un archivo SRT independiente.

8
00:00:28,500 --> 00:00:32,000
Usa la funcionalidad de conversión de VLC.

9
00:00:32,500 --> 00:00:36,000
Navega a Media y luego a Convertir/Guardar.

10
00:00:36,500 --> 00:00:40,000
Selecciona el video y extrae los subtítulos.
EOF

# French subtitle (distractor)
cat > /tmp/french_sub.srt <<'EOF'
1
00:00:01,000 --> 00:00:04,000
Bonjour, ceci est une vidéo d'exemple.

2
00:00:04,500 --> 00:00:08,000
Il démontre l'extraction des sous-titres.

3
00:00:08,500 --> 00:00:12,000
Vous devez extraire la piste anglaise.

4
00:00:12,500 --> 00:00:16,000
Cette vidéo contient plusieurs flux de sous-titres.

5
00:00:16,500 --> 00:00:20,000
Les sous-titres anglais, espagnols et français sont intégrés.

6
00:00:20,500 --> 00:00:24,000
Votre tâche est de sauvegarder les sous-titres anglais.

7
00:00:24,500 --> 00:00:28,000
La sortie doit être un fichier SRT autonome.

8
00:00:28,500 --> 00:00:32,000
Utilisez la fonctionnalité de conversion de VLC.

9
00:00:32,500 --> 00:00:36,000
Accédez à Média puis à Convertir/Enregistrer.

10
00:00:36,500 --> 00:00:40,000
Sélectionnez la vidéo et extrayez les sous-titres.
EOF

# Generate a simple test video with embedded subtitles
VIDEO_FILE="/home/ga/Videos/multilang_video.mkv"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "Generating test video with embedded subtitles..."
    
    # Create a simple 60-second video with color test pattern
    ffmpeg -f lavfi -i testsrc=duration=60:size=1280x720:rate=25 \
           -f lavfi -i sine=frequency=1000:duration=60 \
           -c:v libx264 -preset ultrafast -crf 28 \
           -c:a aac -b:a 128k \
           -y /tmp/base_video.mp4 >/dev/null 2>&1
    
    # Mux video with multiple subtitle tracks
    ffmpeg -i /tmp/base_video.mp4 \
           -i /tmp/english_sub.srt \
           -i /tmp/spanish_sub.srt \
           -i /tmp/french_sub.srt \
           -map 0:v -map 0:a -map 1 -map 2 -map 3 \
           -c:v copy -c:a copy -c:s srt \
           -metadata:s:s:0 language=eng -metadata:s:s:0 title="English" \
           -metadata:s:s:1 language=spa -metadata:s:s:1 title="Spanish" \
           -metadata:s:s:2 language=fre -metadata:s:s:2 title="French" \
           -y "$VIDEO_FILE" >/dev/null 2>&1
    
    chown ga:ga "$VIDEO_FILE"
    echo "✅ Test video created with 3 subtitle tracks"
else
    echo "✅ Test video already exists"
fi

# Verify the video has subtitle tracks
echo "Verifying subtitle tracks in video..."
SUBTITLE_COUNT=$(ffprobe -v error -select_streams s -show_entries stream=index \
                 -of csv=p=0 "$VIDEO_FILE" 2>/dev/null | wc -l)
echo "Found $SUBTITLE_COUNT subtitle track(s) in video"

# Launch VLC with the multi-subtitle video
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show '$VIDEO_FILE' > /tmp/vlc_extract_subs_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Extract Embedded Subtitles Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Video with 3 embedded subtitle tracks is playing"
echo "  2. Press Ctrl+I to open Media Information dialog"
echo "  3. Go to Codec Information tab to see subtitle streams"
echo "  4. Note the English subtitle stream (language=eng)"
echo "  5. Press Ctrl+R to open Convert/Save dialog"
echo "  6. Add the video file: $VIDEO_FILE"
echo "  7. Click Convert/Save button"
echo "  8. In profile settings, ensure subtitles are selected"
echo "  9. Set destination: /home/ga/Videos/subtitles/extracted_english.srt"
echo "  10. Click Start to extract"
echo ""
echo "Alternative approach:"
echo "  - Tools → Codec Information to identify streams"
echo "  - Media → Convert/Save for extraction"