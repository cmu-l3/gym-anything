#!/bin/bash
echo "=== Setting up DJ Setlist task ==="

source /workspace/scripts/task_utils.sh

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count

# Generate 25 song tiddlers
cat << 'EOF' > /tmp/generate_songs.py
import os

songs = [
    ("Come Away With Me", "Norah Jones", "Jazz", "Slow", "Chill", "Song"),
    ("Fly Me to the Moon", "Frank Sinatra", "Jazz", "Medium", "Chill", "Song"),
    ("Banana Pancakes", "Jack Johnson", "Acoustic", "Slow", "Chill", "Song"),
    ("Tears in Heaven", "Eric Clapton", "Acoustic", "Slow", "Chill", "Song DoNotPlay"),
    ("So What", "Miles Davis", "Jazz", "Medium", "Chill", "Song"),
    ("At Last", "Etta James", "R&B", "Slow", "Romantic", "Song"),
    ("Let's Stay Together", "Al Green", "R&B", "Medium", "Romantic", "Song"),
    ("A Thousand Years", "Christina Perri", "Pop", "Slow", "Romantic", "Song DoNotPlay"),
    ("Perfect", "Ed Sheeran", "Pop", "Slow", "Romantic", "Song"),
    ("All of Me", "John Legend", "R&B", "Slow", "Romantic", "Song"),
    ("Uptown Funk", "Mark Ronson ft. Bruno Mars", "Pop", "Fast", "Party", "Song"),
    ("September", "Earth, Wind & Fire", "R&B", "Fast", "Party", "Song"),
    ("Mr. Brightside", "The Killers", "Rock", "Fast", "Party", "Song DoNotPlay"),
    ("Don't Stop Believin'", "Journey", "Rock", "Fast", "Party", "Song"),
    ("I Gotta Feeling", "Black Eyed Peas", "Pop", "Fast", "Party", "Song"),
    ("Levitating", "Dua Lipa", "Pop", "Fast", "Party", "Song"),
    ("Shape of You", "Ed Sheeran", "Pop", "Medium", "Party", "Song"),
    ("Thinking Out Loud", "Ed Sheeran", "Pop", "Slow", "Romantic", "Song"),
    ("Take Five", "Dave Brubeck", "Jazz", "Fast", "Chill", "Song"),
    ("Blackbird", "The Beatles", "Acoustic", "Slow", "Chill", "Song"),
    ("I Will Always Love You", "Whitney Houston", "R&B", "Slow", "Romantic", "Song DoNotPlay"),
    ("Billie Jean", "Michael Jackson", "Pop", "Fast", "Party", "Song"),
    ("Crazy in Love", "Beyonce", "R&B", "Fast", "Party", "Song"),
    ("Superstition", "Stevie Wonder", "R&B", "Fast", "Party", "Song"),
    ("Wonderful Tonight", "Eric Clapton", "Rock", "Slow", "Romantic", "Song")
]

os.makedirs("/home/ga/mywiki/tiddlers", exist_ok=True)

for title, artist, genre, tempo, vibe, tags in songs:
    filename = f"/home/ga/mywiki/tiddlers/{title.replace(' ', '_').replace(',', '').replace(\"'\", '')}.tid"
    content = f"title: {title}\nartist: {artist}\ngenre: {genre}\ntempo: {tempo}\nvibe: {vibe}\ntags: {tags}\ntype: text/vnd.tiddlywiki\n\n"
    with open(filename, "w") as f:
        f.write(content)

EOF

su - ga -c "python3 /tmp/generate_songs.py"

# Restart TiddlyWiki server to pick up new tiddlers properly
echo "Restarting TiddlyWiki server..."
pkill -f "tiddlywiki"
sleep 2
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"
sleep 5

# Refresh TiddlyWiki to load new tiddlers in Firefox
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key F5
sleep 3

take_screenshot /tmp/setup_initial.png
echo "=== Setup Complete ==="