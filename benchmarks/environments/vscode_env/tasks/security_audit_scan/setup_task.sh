#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Security Audit Task ==="

WORKSPACE_DIR="/home/ga/workspace/security_audit"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create vulnerable web app structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/server/routes"
sudo -u ga mkdir -p "$WORKSPACE_DIR/server/utils"
sudo -u ga mkdir -p "$WORKSPACE_DIR/client/components"
sudo -u ga mkdir -p "$WORKSPACE_DIR/config"
sudo -u ga mkdir -p "$WORKSPACE_DIR/db"

# Create vulnerable backend files
cat > "$WORKSPACE_DIR/server/routes/auth.js" << 'EOF'
const express = require('express');
const router = express.Router();
const db = require('../db');

// User login endpoint
router.post('/login', async (req, res) => {
    const { email, password } = req.body;
    
    // VULNERABILITY: SQL Injection via string concatenation
    const query = `SELECT * FROM users WHERE email = '${email}' AND password = '${password}'`;
    
    try {
        const result = await db.query(query);
        if (result.rows.length > 0) {
            res.json({ success: true, user: result.rows[0] });
        } else {
            res.status(401).json({ error: 'Invalid credentials' });
        }
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// User search endpoint
router.get('/search', async (req, res) => {
    const searchTerm = req.query.q;
    
    // VULNERABILITY: SQL Injection in search
    const query = "SELECT * FROM users WHERE username LIKE '%" + searchTerm + "%'";
    
    const result = await db.query(query);
    res.json(result.rows);
});

module.exports = router;
EOF

cat > "$WORKSPACE_DIR/server/routes/admin.js" << 'EOF'
const express = require('express');
const router = express.Router();
const { exec } = require('child_process');

// System diagnostics endpoint
router.get('/ping', (req, res) => {
    const host = req.query.host;
    
    // VULNERABILITY: Command injection
    exec(`ping -c 1 ${host}`, (error, stdout, stderr) => {
        if (error) {
            res.status(500).json({ error: error.message });
            return;
        }
        res.json({ output: stdout });
    });
});

// System info endpoint  
router.get('/sysinfo', (req, res) => {
    const command = req.query.cmd || 'uname -a';
    
    // VULNERABILITY: Command injection via eval
    try {
        const result = eval(`require('child_process').execSync('${command}').toString()`);
        res.json({ result });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;
EOF

cat > "$WORKSPACE_DIR/server/utils/crypto.js" << 'EOF'
const crypto = require('crypto');

// VULNERABILITY: Weak cryptography - MD5 for passwords
function hashPassword(password) {
    return crypto.createHash('md5').update(password).digest('hex');
}

// VULNERABILITY: Hardcoded salt
const SALT = 'hardcoded_salt_12345';

function hashPasswordWithSalt(password) {
    // VULNERABILITY: Still using SHA1 which is weak for passwords
    return crypto.createHash('sha1').update(password + SALT).digest('hex');
}

module.exports = { hashPassword, hashPasswordWithSalt };
EOF

cat > "$WORKSPACE_DIR/config/stripe.js" << 'EOF'
// Payment configuration

// VULNERABILITY: Hardcoded Stripe API key
const STRIPE_SECRET_KEY = "sk_live_51HqX2bKqT8yZpL9fN3mVwE8rQaS7cD6gH2jK4lP5tY9uI1oA3bC6dE8fG0hJ2kL";

// VULNERABILITY: Hardcoded publishable key
const STRIPE_PUBLISHABLE_KEY = "pk_live_51HqX2bKqT8yZpL9fM8nR5sT2wQ9aB4cD7eF1gH3iJ6kL2mN8oP5qR";

module.exports = {
    stripeSecretKey: STRIPE_SECRET_KEY,
    stripePublishableKey: STRIPE_PUBLISHABLE_KEY
};
EOF

cat > "$WORKSPACE_DIR/config/aws.js" << 'EOF'
// AWS Configuration

// VULNERABILITY: Hardcoded AWS credentials
const AWS_ACCESS_KEY_ID = "AKIAIOSFODNN7EXAMPLE";
const AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
const AWS_REGION = "us-west-2";

module.exports = {
    accessKeyId: AWS_ACCESS_KEY_ID,
    secretAccessKey: AWS_SECRET_ACCESS_KEY,
    region: AWS_REGION
};
EOF

cat > "$WORKSPACE_DIR/config/database.js" << 'EOF'
// Database configuration

// VULNERABILITY: Hardcoded database password
const DB_CONFIG = {
    host: 'localhost',
    port: 5432,
    database: 'myapp',
    user: 'admin',
    password: 'SuperSecret123!AdminPass'
};

module.exports = DB_CONFIG;
EOF

# Create vulnerable frontend files
cat > "$WORKSPACE_DIR/client/components/Comment.js" << 'EOF'
import React from 'react';

function Comment({ comment }) {
    // VULNERABILITY: XSS via dangerouslySetInnerHTML
    return (
        <div className="comment">
            <div className="author">{comment.author}</div>
            <div 
                className="content" 
                dangerouslySetInnerHTML={{ __html: comment.text }}
            />
            <div className="timestamp">{comment.timestamp}</div>
        </div>
    );
}

export default Comment;
EOF

cat > "$WORKSPACE_DIR/client/components/UserProfile.js" << 'EOF'
import React, { useEffect, useRef } from 'react';

function UserProfile({ user }) {
    const bioRef = useRef(null);
    
    useEffect(() => {
        if (bioRef.current && user.bio) {
            // VULNERABILITY: XSS via innerHTML
            bioRef.current.innerHTML = user.bio;
        }
    }, [user.bio]);
    
    return (
        <div className="profile">
            <h2>{user.name}</h2>
            <div ref={bioRef} className="bio"></div>
        </div>
    );
}

export default UserProfile;
EOF

cat > "$WORKSPACE_DIR/client/components/SearchResults.js" << 'EOF'
import React from 'react';

function SearchResults({ results, query }) {
    return (
        <div className="search-results">
            <h3>Search Results for: {query}</h3>
            {results.map((result, idx) => (
                <div key={idx} className="result-item">
                    {/* VULNERABILITY: Potential XSS if result.highlight contains HTML */}
                    <div dangerouslySetInnerHTML={{ __html: result.highlight }} />
                    <p>{result.description}</p>
                </div>
            ))}
        </div>
    );
}

export default SearchResults;
EOF

# Create SQL files
cat > "$WORKSPACE_DIR/db/queries.sql" << 'EOF'
-- User queries

-- VULNERABILITY: Example of SQL injection pattern in comments
-- This query should be parameterized:
-- SELECT * FROM users WHERE id = $1
-- Instead of: SELECT * FROM users WHERE id = '${userId}'

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Note: Password should be hashed with bcrypt, not MD5
INSERT INTO users (email, password) VALUES 
    ('admin@example.com', '5f4dcc3b5aa765d61d8327deb882cf99');
EOF

# Create README for the vulnerable app
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# My Web Application

A simple Express.js + React web application for managing users and content.

## Features

- User authentication
- Comment system
- Admin dashboard
- Payment integration (Stripe)
- Cloud storage (AWS S3)

## Setup
