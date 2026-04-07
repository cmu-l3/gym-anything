#!/bin/bash
echo "=== Setting up Firefox Reader View Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/Documents/clean_story.pdf 2>/dev/null || true
rm -f /tmp/clean_story.pdf 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 1. Setup the local web server with a cluttered web page
# The HTML is specifically designed to trigger Readability.js (Reader View)
# while containing obvious clutter that should be excluded.
STORY_DIR="/tmp/story_site"
mkdir -p "$STORY_DIR"

cat > "$STORY_DIR/story.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Classic Literature - The Tell-Tale Heart</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 0; background: #f9f9f9; }
        header { background: #333; color: white; padding: 20px; text-align: center; }
        nav { background: #0055a4; color: white; padding: 15px; }
        nav ul { list-style: none; margin: 0; padding: 0; display: flex; gap: 20px; }
        nav a { color: white; text-decoration: none; font-weight: bold; }
        .container { display: flex; max-width: 1200px; margin: 20px auto; gap: 30px; }
        main { flex: 3; background: white; padding: 30px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        aside { flex: 1; }
        .ad-box { background: #ffebee; border: 2px dashed #f44336; padding: 20px; text-align: center; margin-bottom: 20px; }
        .ad-box h3 { color: #d32f2f; margin-top: 0; }
        article { font-size: 18px; line-height: 1.6; color: #333; }
    </style>
</head>
<body>
    <header>
        <h1>Classic Literature Hub</h1>
    </header>
    
    <nav>
        <ul>
            <li><a href="#">Home</a></li>
            <li><a href="#">More Stories</a></li>
            <li><a href="#" style="color: yellow;">CLICK HERE TO SUBSCRIBE</a></li>
            <li><a href="#">About Us</a></li>
        </ul>
    </nav>

    <div class="container">
        <main>
            <article>
                <h1>The Tell-Tale Heart</h1>
                <p><strong>By Edgar Allan Poe</strong></p>
                
                <p>TRUE! --nervous --very, very dreadfully nervous I had been and am; but why will you say that I am mad? The disease had sharpened my senses --not destroyed --not dulled them. Above all was the sense of hearing acute. I heard all things in the heaven and in the earth. I heard many things in hell. How, then, am I mad? Hearken! and observe how healthily --how calmly I can tell you the whole story.</p>
                
                <p>It is impossible to say how first the idea entered my brain; but once conceived, it haunted me day and night. Object there was none. Passion there was none. I loved the old man. He had never wronged me. He had never given me insult. For his gold I had no desire. I think it was his eye! yes, it was this! He had the eye of a vulture --a pale blue eye, with a film over it. Whenever it fell upon me, my blood ran cold; and so by degrees --very gradually --I made up my mind to take the life of the old man, and thus rid myself of the eye forever.</p>
                
                <p>Now this is the point. You fancy me mad. Madmen know nothing. But you should have seen me. You should have seen how wisely I proceeded --with what caution --with what foresight --with what dissimulation I went to work! I was never kinder to the old man than during the whole week before I killed him. And every night, about midnight, I turned the latch of his door and opened it --oh so gently!</p>
                
                <p>And then, when I had made an opening sufficient for my head, I put in a dark lantern, all closed, closed, that no light shone out, and then I thrust in my head. Oh, you would have laughed to see how cunningly I thrust it in! I moved it slowly --very, very slowly, so that I might not disturb the old man's sleep. It took me an hour to place my whole head within the opening so far that I could see him as he lay upon his bed. Ha! would a madman have been so wise as this?</p>
            </article>
        </main>
        
        <aside>
            <div class="ad-box">
                <h3>SPONSORED ADVERTISEMENT</h3>
                <p>Buy our amazing new brain-boosting supplements today! Enhance your focus and memory.</p>
                <button>BUY NOW 50% OFF</button>
            </div>
            <div class="ad-box" style="background: #e8f5e9; border-color: #4caf50;">
                <h3 style="color: #388e3c;">LEARN TO WRITE</h3>
                <p>Join our masterclass and become the next great author. Enroll today!</p>
            </div>
        </aside>
    </div>
</body>
</html>
EOF

# Start python http server in the background
cd "$STORY_DIR"
python3 -m http.server 8080 > /tmp/http_server.log 2>&1 &
SERVER_PID=$!
echo "Started local web server at PID: $SERVER_PID"

# Wait a moment for server to bind
sleep 2

# 2. Start Firefox
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    # Start on a blank page so the agent must navigate
    su - ga -c "DISPLAY=:1 firefox about:blank &"
    sleep 5
fi

# 3. Maximize and focus Firefox
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox"; then
        DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="