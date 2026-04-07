#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Secure Web Application Task ==="

WORKSPACE_DIR="/home/ga/workspace/securenotes"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Create directory structure
sudo -u ga mkdir -p routes views db uploads

# ─────────────────────────────────────────────────────────────
# Create Application Files (Vulnerable)
# ─────────────────────────────────────────────────────────────

# package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "securenotes",
  "version": "1.0.0",
  "description": "A note taking application",
  "main": "app.js",
  "dependencies": {
    "ejs": "^3.1.9",
    "express": "^4.18.2",
    "express-session": "^1.17.3",
    "sqlite3": "^5.1.6"
  }
}
EOF

# db/setup.js
cat > "$WORKSPACE_DIR/db/setup.js" << 'EOF'
const sqlite3 = require('sqlite3').verbose();
const db = new sqlite3.Database(':memory:');

db.serialize(() => {
    db.run("CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, password TEXT)");
    db.run("CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT, content TEXT, category TEXT)");
    
    // Seed data
    db.run("INSERT INTO users (username, password) VALUES ('admin', 'admin123')");
    db.run("INSERT INTO notes (title, content, category) VALUES ('Welcome', 'This is your first note.', 'General')");
});

module.exports = db;
EOF

# app.js (V5: Insecure Session Configuration)
cat > "$WORKSPACE_DIR/app.js" << 'EOF'
const express = require('express');
const session = require('express-session');
const app = express();

app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// V5: VULNERABILITY - Insecure Session Configuration
app.use(session({
    secret: 'super-secret-keyboard-cat',
    resave: false,
    saveUninitialized: true,
    cookie: {} 
}));

app.set('view engine', 'ejs');
app.set('views', './views');

app.use('/auth', require('./routes/auth'));
app.use('/notes', require('./routes/notes'));
app.use('/files', require('./routes/files'));
app.use('/api', require('./routes/api'));

app.listen(3000, () => console.log('Server running on port 3000'));
EOF

# routes/auth.js (V1: SQL Injection, V4: Plaintext Passwords)
cat > "$WORKSPACE_DIR/routes/auth.js" << 'EOF'
const express = require('express');
const router = express.Router();
const db = require('../db/setup');

router.post('/login', (req, res) => {
    // V1 & V4: VULNERABILITY - SQL Injection and Plaintext Password Comparison
    const query = "SELECT * FROM users WHERE username = '" + req.body.username + "' AND password = '" + req.body.password + "'";
    
    db.get(query, (err, user) => {
        if (err) return res.status(500).send('Database error');
        if (user) {
            req.session.userId = user.id;
            res.redirect('/notes');
        } else {
            res.status(401).send('Invalid credentials');
        }
    });
});

router.post('/register', (req, res) => {
    // V1 & V4: VULNERABILITY - SQL Injection and Plaintext Password Storage
    const query = "INSERT INTO users (username, password) VALUES ('" + req.body.username + "', '" + req.body.password + "')";
    
    db.run(query, (err) => {
        if (err) return res.status(500).send('Database error');
        res.redirect('/login');
    });
});

module.exports = router;
EOF

# routes/notes.js
cat > "$WORKSPACE_DIR/routes/notes.js" << 'EOF'
const express = require('express');
const router = express.Router();
const db = require('../db/setup');

router.get('/', (req, res) => {
    if (!req.session.userId) return res.redirect('/login');
    
    db.all("SELECT * FROM notes", (err, notes) => {
        if (err) return res.status(500).send('Database error');
        res.render('notes', { notes });
    });
});

module.exports = router;
EOF

# views/notes.ejs (V2: Stored XSS)
cat > "$WORKSPACE_DIR/views/notes.ejs" << 'EOF'
<!DOCTYPE html>
<html>
<head><title>SecureNotes</title></head>
<body>
    <h1>Your Notes</h1>
    <% notes.forEach(function(note) { %>
        <div class="note">
            <h3><%= note.title %></h3>
            <!-- V2: VULNERABILITY - Stored XSS via unescaped output -->
            <div class="content"><%- note.content %></div>
            <div class="meta">Category: <%= note.category %></div>
        </div>
    <% }); %>
</body>
</html>
EOF

# routes/files.js (V3: Path Traversal)
cat > "$WORKSPACE_DIR/routes/files.js" << 'EOF'
const express = require('express');
const path = require('path');
const router = express.Router();

router.get('/download/:filename', (req, res) => {
    if (!req.session.userId) return res.status(403).send('Forbidden');
    
    const uploadsDir = path.join(__dirname, '../uploads');
    
    // V3: VULNERABILITY - Path Traversal
    const filePath = path.join(uploadsDir, req.params.filename);
    
    res.sendFile(filePath, (err) => {
        if (err) res.status(404).send('File not found');
    });
});

module.exports = router;
EOF

# routes/api.js (V6: Missing Input Validation)
cat > "$WORKSPACE_DIR/routes/api.js" << 'EOF'
const express = require('express');
const router = express.Router();
const db = require('../db/setup');

router.post('/notes', (req, res) => {
    // V6: VULNERABILITY - Missing Input Validation
    const { title, content, category } = req.body;
    
    db.run("INSERT INTO notes (title, content, category) VALUES (?, ?, ?)", [title, content, category], function(err) {
        if (err) return res.status(500).json({ error: 'Database error' });
        res.json({ success: true, id: this.lastID });
    });
});

module.exports = router;
EOF

# pentest_report.md
cat > "$WORKSPACE_DIR/pentest_report.md" << 'EOF'
# Penetration Test Report - SecureNotes

**Date:** October 12, 2024
**Target:** SecureNotes Web Application
**Status:** 6 Critical/High Findings

## Findings Summary

| ID | Vulnerability | Severity | CWE | Location |
|----|---------------|----------|-----|----------|
| V1 | SQL Injection | Critical | CWE-89 | `routes/auth.js` |
| V2 | Stored Cross-Site Scripting (XSS) | High | CWE-79 | `views/notes.ejs` |
| V3 | Path Traversal | High | CWE-22 | `routes/files.js` |
| V4 | Plaintext Password Storage | Critical | CWE-256 | `routes/auth.js` |
| V5 | Insecure Session Configuration | Medium | CWE-614 | `app.js` |
| V6 | Missing Input Validation | Medium | CWE-20 | `routes/api.js` |

## Finding Details

### V1: SQL Injection
**Description:** The login and register endpoints construct SQL queries by concatenating raw user input.
**Remediation:** Use parameterized queries (prepared statements) with `?` placeholders for all database operations.

### V2: Stored XSS
**Description:** Note content is rendered in the EJS template without HTML escaping, allowing malicious scripts to execute in the victim's browser.
**Remediation:** Use EJS's escaped output tag (`<%=`) instead of the unescaped tag (`<%-`) for rendering user-supplied content.

### V3: Path Traversal
**Description:** The file download endpoint allows directory traversal via `../` payloads, allowing attackers to read arbitrary files on the server (e.g., `/files/download/..%2f..%2f..%2fetc%2fpasswd`).
**Remediation:** Use `path.resolve()` and ensure the resolved absolute path starts with the intended uploads directory base path.

### V4: Plaintext Password Storage
**Description:** Passwords are saved to the database in plaintext.
**Remediation:** Hash passwords securely using `bcrypt` (or `argon2`) on registration, and use the library's compare function during login.

### V5: Insecure Session Configuration
**Description:** The express-session cookie lacks essential security flags.
**Remediation:** Configure the session cookie with `httpOnly: true` and `sameSite: 'strict'` (or 'lax').

### V6: Missing Input Validation
**Description:** The API endpoint for creating notes accepts arbitrary data types and lengths, potentially causing application crashes or database truncation.
**Remediation:** Implement basic input validation (e.g., checking that title and content exist, are strings, and have reasonable length limits).
EOF

# Set ownership
chown -R ga:ga "$WORKSPACE_DIR"

# Install initial dependencies
su - ga -c "cd $WORKSPACE_DIR && npm install --silent"

# Record task start time and initial file checksums
date +%s > /tmp/task_start_time.txt
find "$WORKSPACE_DIR" -type f -name "*.js" -o -name "*.ejs" -exec md5sum {} + > /tmp/initial_checksums.txt

# Start VSCode
echo "Starting VSCode..."
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/pentest_report.md $WORKSPACE_DIR/routes/auth.js &"
sleep 5

# Maximize and focus
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="