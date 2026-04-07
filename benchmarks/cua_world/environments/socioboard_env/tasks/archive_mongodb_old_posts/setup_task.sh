#!/bin/bash
echo "=== Setting up archive_mongodb_old_posts task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure MongoDB is running
systemctl start mongod 2>/dev/null || true
sleep 3

# Wait for MongoDB readiness
for i in $(seq 1 30); do
  if mongosh --quiet --eval "db.runCommand({ping: 1})" --norc 2>/dev/null | grep -qE 'ok.*1|"ok".*1'; then
    echo "MongoDB ready"
    break
  fi
  sleep 2
done

# Prepare JS file for MongoDB insertion
cat > /tmp/setup_mongo_posts.js << 'EOF'
use socioboard;
db.published_posts.drop();

var networks = ["facebook", "twitter", "linkedin", "instagram"];
var messages = [
  "Check out our new product launch! 🚀",
  "We are thrilled to announce our Q3 earnings.",
  "Join us at the annual tech conference this week.",
  "Happy holidays to all our amazing customers! 🎄",
  "Customer spotlight: How Company X scaled using our platform.",
  "5 tips for better social media engagement. Read more on our blog.",
  "We're hiring! Check out our careers page for open roles.",
  "Our system will be undergoing scheduled maintenance this weekend.",
  "Thanks for 1 million followers! We couldn't have done it without you.",
  "Watch our latest webinar on digital transformation."
];

var posts = [];
// Generate exactly 432 old posts (before 2023)
var startOld = new Date("2020-01-01T00:00:00Z").getTime();
var endOld = new Date("2022-12-31T23:59:59Z").getTime();
for(var i=0; i<432; i++) {
  var dt = new Date(startOld + Math.random() * (endOld - startOld));
  posts.push({
    post_id: "post_old_" + i,
    network: networks[Math.floor(Math.random() * networks.length)],
    published_date: dt,
    content: messages[Math.floor(Math.random() * messages.length)] + " " + i,
    status: "published"
  });
}

// Generate exactly 568 recent posts (2023 and later)
var startRecent = new Date("2023-01-01T00:00:00Z").getTime();
var endRecent = new Date("2024-10-01T00:00:00Z").getTime();
for(var i=0; i<568; i++) {
  var dt = new Date(startRecent + Math.random() * (endRecent - startRecent));
  posts.push({
    post_id: "post_new_" + i,
    network: networks[Math.floor(Math.random() * networks.length)],
    published_date: dt,
    content: messages[Math.floor(Math.random() * messages.length)] + " " + i,
    status: "published"
  });
}

db.published_posts.insertMany(posts);
print("Inserted 432 old posts and 568 recent posts successfully.");
EOF

# Execute the script
MONGO_SHELL="mongosh"
if ! command -v mongosh >/dev/null 2>&1; then
    MONGO_SHELL="mongo"
fi

$MONGO_SHELL --quiet socioboard /tmp/setup_mongo_posts.js

# Remove previous archives if any
rm -rf /home/ga/Archives 2>/dev/null || true

# Launch terminal for the user
if ! pgrep -f "gnome-terminal\|xterm\|terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 x-terminal-emulator &"
    sleep 3
fi

# Maximize active window (which should be the new terminal)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="