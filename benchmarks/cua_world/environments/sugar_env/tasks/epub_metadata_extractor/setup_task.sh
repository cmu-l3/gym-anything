#!/bin/bash
echo "=== Setting up epub_metadata_extractor task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp
date +%s > /tmp/task_start_ts
chmod 666 /tmp/task_start_ts

# Create necessary directories
mkdir -p /home/ga/Documents/library
mkdir -p /var/lib/app/ground_truth
chown -R ga:ga /home/ga/Documents

# Clean up any existing files from previous runs
rm -f /home/ga/Documents/build_catalog.py
rm -f /home/ga/Documents/library_catalog.txt
rm -rf /home/ga/Documents/library/*

# Helper function to create a minimal valid EPUB in case Gutenberg download fails
create_fallback_epub() {
    local file=$1
    local title=$2
    local author=$3
    
    mkdir -p /tmp/epub_gen/META-INF
    echo -n "application/epub+zip" > /tmp/epub_gen/mimetype
    cat > /tmp/epub_gen/META-INF/container.xml <<EOF
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
EOF
    cat > /tmp/epub_gen/content.opf <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    <dc:creator>$author</dc:creator>
  </metadata>
</package>
EOF
    cd /tmp/epub_gen
    zip -q0X "$file" mimetype
    zip -qXr9D "$file" META-INF content.opf
    cd - > /dev/null
    rm -rf /tmp/epub_gen
    chown ga:ga "$file"
}

# Download real EPUBs from Project Gutenberg (noimages versions for speed)
echo "Fetching real EPUB data..."

# Book 1: Frankenstein
wget -q -O /home/ga/Documents/library/pg84.epub "https://www.gutenberg.org/ebooks/84.epub.noimages" || true
if [ ! -s /home/ga/Documents/library/pg84.epub ] || [ $(stat -c%s /home/ga/Documents/library/pg84.epub) -lt 1000 ]; then
    create_fallback_epub "/home/ga/Documents/library/pg84.epub" "Frankenstein; Or, The Modern Prometheus" "Mary Wollstonecraft Shelley"
fi

# Book 2: Pride and Prejudice
wget -q -O /home/ga/Documents/library/pg1342.epub "https://www.gutenberg.org/ebooks/1342.epub.noimages" || true
if [ ! -s /home/ga/Documents/library/pg1342.epub ] || [ $(stat -c%s /home/ga/Documents/library/pg1342.epub) -lt 1000 ]; then
    create_fallback_epub "/home/ga/Documents/library/pg1342.epub" "Pride and Prejudice" "Jane Austen"
fi

# Book 3: A Tale of Two Cities
wget -q -O /home/ga/Documents/library/pg98.epub "https://www.gutenberg.org/ebooks/98.epub.noimages" || true
if [ ! -s /home/ga/Documents/library/pg98.epub ] || [ $(stat -c%s /home/ga/Documents/library/pg98.epub) -lt 1000 ]; then
    create_fallback_epub "/home/ga/Documents/library/pg98.epub" "A Tale of Two Cities" "Charles Dickens"
fi

# Hidden Book (For dynamic testing): Alice in Wonderland
wget -q -O /var/lib/app/ground_truth/pg11.epub "https://www.gutenberg.org/ebooks/11.epub.noimages" || true
if [ ! -s /var/lib/app/ground_truth/pg11.epub ] || [ $(stat -c%s /var/lib/app/ground_truth/pg11.epub) -lt 1000 ]; then
    create_fallback_epub "/var/lib/app/ground_truth/pg11.epub" "Alice's Adventures in Wonderland" "Lewis Carroll"
fi

chmod 644 /home/ga/Documents/library/*.epub
chmod 644 /var/lib/app/ground_truth/*.epub

# Close any open activity to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Start the Terminal Activity for the agent
su - ga -c "$SUGAR_ENV sugar-launch sugar-terminal-activity" &
sleep 5

# Take initial screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="