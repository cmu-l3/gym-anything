#!/bin/bash
echo "=== Setting up purge_spam_rss_articles task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure MongoDB is running
systemctl is-active --quiet mongod || sudo systemctl start mongod
sleep 3

# Wait for MongoDB readiness
for i in {1..30}; do
  if mongosh --quiet --eval "db.runCommand({ping: 1})" --norc 2>/dev/null | grep -qE 'ok.*1|"ok".*1'; then
    echo "MongoDB is ready."
    break
  fi
  sleep 1
done

# Generate a secret token to embed in a legitimate document (Anti-Gaming)
# If the agent drops the collection and creates a fake one, this token will be lost.
SECRET_TOKEN=$(head -c 16 /dev/urandom | xxd -p)
echo "$SECRET_TOKEN" > /tmp/secret_token.txt

echo "Seeding rss_articles collection..."

# Create a Node.js/mongosh script to reliably insert complex data
cat > /tmp/seed_db.js << EOF
use socioboard;

// Ensure clean state
db.rss_articles.drop();

let legit_docs = [];
for (let i = 0; i < 150; i++) {
    let doc = {
        title: "Technology and Business Update " + i,
        description: "This is a legitimate news article covering recent updates in the technology sector. Article ID: " + i,
        publishedDate: new Date(),
        link: "http://news.example.com/article/" + i,
        author: "Tech Reporter",
        is_spam: false
    };
    // Embed secret token in the first legitimate document
    if (i === 0) {
        doc.secret_token = "$SECRET_TOKEN";
    }
    legit_docs.push(doc);
}
db.rss_articles.insertMany(legit_docs);

let spam_docs = [];
for (let i = 0; i < 42; i++) {
    // Vary the casing to require case-insensitive regex
    let keyword = "crypto-giveaway";
    if (i % 2 === 0) keyword = "Crypto-Giveaway";
    if (i % 3 === 0) keyword = "CRYPTO-GIVEAWAY";
    
    // Distribute keyword between title and description
    let in_title = (i % 2 === 0);
    
    spam_docs.push({
        title: in_title ? "HUGE " + keyword + " CLAIM NOW!" : "Normal looking title " + i,
        description: in_title ? "Check out the link below." : "Click here to participate in the " + keyword + " scam!",
        publishedDate: new Date(),
        link: "http://scam-site.example.com/claim/" + i,
        author: "Unknown",
        is_spam: true
    });
}
db.rss_articles.insertMany(spam_docs);

print("SEED_COMPLETE");
EOF

# Execute the seed script
mongosh --quiet --norc /tmp/seed_db.js > /tmp/seed_output.txt 2>&1

if grep -q "SEED_COMPLETE" /tmp/seed_output.txt; then
    echo "Database seeded successfully."
else
    echo "ERROR: Database seeding failed!"
    cat /tmp/seed_output.txt
fi

# Open a terminal window for the agent to use
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga --maximize &" 2>/dev/null || \
su - ga -c "DISPLAY=:1 x-terminal-emulator &" 2>/dev/null || true
sleep 3

# Take initial screenshot showing terminal
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="