#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Prepare Async Workshop Task ==="

WORKSHOP_DIR="/home/ga/workshop"

# Clean up any existing workshop directory
if [ -d "$WORKSHOP_DIR" ]; then
    echo "Cleaning existing workshop directory..."
    sudo rm -rf "$WORKSHOP_DIR"
fi

# Create workshop directory
sudo -u ga mkdir -p "$WORKSHOP_DIR"

# Create the "messy" starting file (complex production code for reference)
cat > "$WORKSHOP_DIR/messy-example.js" << 'EOF'
// Complex production code - needs simplification for teaching
// This demonstrates real-world callback complexity that you'll simplify into teaching examples

const db = require('./db');
const cache = require('./cache');
const analytics = require('./analytics');

function getUserData(userId, callback) {
    db.users.findById(userId, (err, user) => {
        if (err) return callback(err);
        cache.get('posts:' + user.id, (err, cachedPosts) => {
            if (err) return callback(err);
            if (cachedPosts) {
                analytics.track('cache_hit', {userId: user.id}, (err) => {
                    if (err) console.error(err);
                    callback(null, {user, posts: cachedPosts});
                });
            } else {
                db.posts.findByUser(user.id, (err, posts) => {
                    if (err) return callback(err);
                    cache.set('posts:' + user.id, posts, 3600, (err) => {
                        if (err) console.error(err);
                        analytics.track('cache_miss', {userId: user.id}, (err) => {
                            if (err) console.error(err);
                            callback(null, {user, posts});
                        });
                    });
                });
            }
        });
    });
}

// TODO: Simplify this into progressive teaching examples:
// 1. Show the callback hell problem (01-callbacks-problem.js)
// 2. Improve with named functions (02-callbacks-fixed.js)
// 3. Refactor to Promises (03-promises-basics.js)
// 4. Modernize with async/await (04-async-await.js)
// 5. Add error handling examples (05-error-handling.js)
// 6. Show parallel operations (06-parallel-async.js)
// 7. Create mock API for offline demos (mock-api.js)

module.exports = {getUserData};
EOF

# Create minimal package.json
cat > "$WORKSHOP_DIR/package.json" << 'EOF'
{
  "name": "async-workshop",
  "version": "1.0.0",
  "description": "Workshop materials for understanding async JavaScript"
}
EOF

# Set permissions
sudo chown -R ga:ga "$WORKSHOP_DIR"

echo "Workshop directory created at: $WORKSHOP_DIR"
echo "Starting files:"
echo "  - messy-example.js (complex production code for reference)"
echo "  - package.json (minimal)"

# Open VSCode with workshop directory
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSHOP_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Prepare Async Workshop Task Setup Complete ==="
echo ""
echo "📚 Workshop Preparation Instructions:"
echo ""
echo "Your goal: Prepare a complete teaching workspace for tomorrow's workshop"
echo ""
echo "Context:"
echo "  - Teaching 15 intermediate bootcamp students"
echo "  - Topic: Async JavaScript (callbacks → promises → async/await)"
echo "  - Constraints: Unreliable wifi, low-res projector, colorblind student"
echo ""
echo "Required deliverables:"
echo ""
echo "1. Progressive JavaScript examples (6 files):"
echo "   - 01-callbacks-problem.js: Nested callbacks showing 'callback hell'"
echo "   - 02-callbacks-fixed.js: Improved with named functions"
echo "   - 03-promises-basics.js: Promise-based refactor"
echo "   - 04-async-await.js: Modern async/await"
echo "   - 05-error-handling.js: Common mistakes + corrections"
echo "   - 06-parallel-async.js: Promise.all for concurrent operations"
echo ""
echo "2. Mock API (mock-api.js):"
echo "   - Functions that return Promises with setTimeout"
echo "   - Must work offline (no real HTTP calls)"
echo "   - Example: fetchUser(), fetchPosts(), fetchComments()"
echo ""
echo "3. VSCode configuration (.vscode/):"
echo "   - settings.json: Large fonts (16+), high contrast theme, no minimap"
echo "   - launch.json: Node.js debug configuration"
echo ""
echo "4. Documentation (README.md):"
echo "   - Workshop objectives"
echo "   - File execution order"
echo "   - Running instructions"
echo ""
echo "All code must include explanatory comments for students!"
echo ""
echo "Reference: messy-example.js shows production complexity to simplify"