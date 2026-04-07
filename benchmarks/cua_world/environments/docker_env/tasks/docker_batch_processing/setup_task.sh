#!/bin/bash
set -e
echo "=== Setting up Docker Batch Processing Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker
if type wait_for_docker &>/dev/null; then
    wait_for_docker
else
    sleep 5
fi

# Define paths
CORPUS_DIR="/home/ga/projects/book-corpus"
RESULTS_DIR="$CORPUS_DIR/results"

# clean up previous runs
echo "Cleaning up previous runs..."
docker rm -f $(docker ps -a -q --filter ancestor=book-analyzer:latest) 2>/dev/null || true
docker rmi book-analyzer:latest 2>/dev/null || true
rm -rf "$CORPUS_DIR"
mkdir -p "$CORPUS_DIR"
chown ga:ga "$CORPUS_DIR"

# Download books (using curl with retry logic)
echo "Downloading corpus data..."
download_book() {
    local url="$1"
    local filename="$2"
    echo "Downloading $filename..."
    if ! curl -L -s --retry 3 --retry-delay 2 -o "$CORPUS_DIR/$filename" "$url"; then
        echo "Failed to download $filename. Creating fallback dummy data."
        # Fallback for offline/restricted environments to ensure task is playable
        for i in {1..1000}; do echo "This is a fallback line of text for $filename." >> "$CORPUS_DIR/$filename"; done
    fi
}

download_book "https://www.gutenberg.org/cache/epub/1342/pg1342.txt" "pride_and_prejudice.txt"
download_book "https://www.gutenberg.org/cache/epub/2701/pg2701.txt" "moby_dick.txt"
download_book "https://www.gutenberg.org/cache/epub/1661/pg1661.txt" "sherlock_holmes.txt"
download_book "https://www.gutenberg.org/cache/epub/84/pg84.txt" "frankenstein.txt"
download_book "https://www.gutenberg.org/cache/epub/11/pg11.txt" "alice_in_wonderland.txt"

# Ensure permissions
chown -R ga:ga "/home/ga/projects"
chmod -R 644 "$CORPUS_DIR"/*.txt

# Record start time
date +%s > /tmp/task_start_time.txt

# Open terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/book-corpus && echo \"Batch Processing Pipeline Task\"; echo \"Data: $(ls *.txt | wc -l) books in $(pwd)\"; echo; ls -lh; exec bash'" > /tmp/terminal_launch.log 2>&1 &
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="