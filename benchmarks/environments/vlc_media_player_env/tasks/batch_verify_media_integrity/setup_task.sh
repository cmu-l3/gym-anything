#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Batch Verify Media Integrity Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create directory structure
echo "Creating directory structure..."
mkdir -p /home/ga/Videos/to_verify
mkdir -p /home/ga/Videos/verified_good
chown -R ga:ga /home/ga/Videos/to_verify
chown -R ga:ga /home/ga/Videos/verified_good

# Clear any existing files in directories
rm -f /home/ga/Videos/to_verify/*
rm -f /home/ga/Videos/verified_good/*
rm -f /home/ga/Videos/verification_report.txt

# Generate test video files
echo "Generating test video files..."

# Movie 1: Working MP4 (10 seconds, 640x480)
su - ga -c "ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 \
    -f lavfi -i sine=frequency=440:duration=10 \
    -pix_fmt yuv420p -c:v libx264 -c:a aac \
    /home/ga/Videos/to_verify/movie_1.mp4 -y -loglevel error" 2>/dev/null || true

# Movie 2: Working MKV (10 seconds, 640x480)
su - ga -c "ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 \
    -f lavfi -i sine=frequency=880:duration=10 \
    -pix_fmt yuv420p -c:v libx264 -c:a aac \
    /home/ga/Videos/to_verify/movie_2.mkv -y -loglevel error" 2>/dev/null || true

# Movie 4: Working MP4 (10 seconds, 640x480)
su - ga -c "ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 \
    -f lavfi -i sine=frequency=660:duration=10 \
    -pix_fmt yuv420p -c:v libx264 -c:a aac \
    /home/ga/Videos/to_verify/movie_4.mp4 -y -loglevel error" 2>/dev/null || true

# Movie 3: Corrupted AVI (generate then truncate)
echo "Creating corrupted video file..."
su - ga -c "ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 \
    -f lavfi -i sine=frequency=220:duration=10 \
    -pix_fmt yuv420p -c:v libx264 -c:a mp3 \
    /tmp/movie_3_temp.avi -y -loglevel error" 2>/dev/null || true

# Truncate to 30% to create corruption
if [ -f /tmp/movie_3_temp.avi ]; then
    SIZE=$(stat -c%s /tmp/movie_3_temp.avi 2>/dev/null || stat -f%z /tmp/movie_3_temp.avi)
    TRUNCATE_SIZE=$((SIZE * 30 / 100))
    dd if=/tmp/movie_3_temp.avi of=/home/ga/Videos/to_verify/movie_3.avi bs=1 count=$TRUNCATE_SIZE 2>/dev/null
    chown ga:ga /home/ga/Videos/to_verify/movie_3.avi
    rm -f /tmp/movie_3_temp.avi
fi

# Verify files were created
echo "Verifying test files..."
ls -lh /home/ga/Videos/to_verify/

# Set proper permissions
chown -R ga:ga /home/ga/Videos/to_verify
chmod 755 /home/ga/Videos/to_verify
chmod 644 /home/ga/Videos/to_verify/*

# Don't launch VLC - agent should do that
echo "=== Batch Verify Media Integrity Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Test each video file in /home/ga/Videos/to_verify/:"
echo "     - movie_1.mp4"
echo "     - movie_2.mkv"
echo "     - movie_3.avi (corrupted)"
echo "     - movie_4.mp4"
echo "  2. Open each file in VLC and check if it plays correctly"
echo "  3. Copy ONLY working files to /home/ga/Videos/verified_good/"
echo "  4. Create verification report: /home/ga/Videos/verification_report.txt"
echo "     Report should list which files passed and which failed"
echo ""
echo "  Hint: movie_3.avi is corrupted and should be excluded"