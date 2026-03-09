#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Syntax Highlighting Task ==="

WORKSPACE_DIR="/home/ga/workspace/template_project"
TEMPLATES_DIR="$WORKSPACE_DIR/templates"
SRC_DIR="$WORKSPACE_DIR/src"

# Create project structure
sudo -u ga mkdir -p "$TEMPLATES_DIR"
sudo -u ga mkdir -p "$SRC_DIR"

# Create sample .tpl files with realistic template content
cat > "$TEMPLATES_DIR/home.tpl" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>{{ pageTitle }}</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body>
    <h1>Welcome {{ userName }}!</h1>
    
    <div class="content">
        {{#if showProducts}}
            <ul class="product-list">
                {{#each products}}
                    <li class="product-item">
                        <span>{{ this.name }}</span> - 
                        <strong>${{ this.price }}</strong>
                    </li>
                {{/each}}
            </ul>
        {{else}}
            <p class="empty-message">No products available.</p>
        {{/if}}
    </div>
    
    <script>
        const user = "{{ userName }}";
        console.log(`Hello, ${user}!`);
        document.addEventListener('DOMContentLoaded', function() {
            console.log('Page loaded');
        });
    </script>
</body>
</html>
EOF

cat > "$TEMPLATES_DIR/product.tpl" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>{{ product.name }}</title>
    <link rel="stylesheet" href="/styles.css">
</head>
<body>
    <div class="product-detail">
        <h2>{{ product.name }}</h2>
        <p class="price">${{ product.price }}</p>
        <p class="description">{{ product.description }}</p>
        
        {{#if product.inStock}}
            <button onclick="addToCart('{{ product.id }}')">Add to Cart</button>
        {{else}}
            <span class="out-of-stock">Out of Stock</span>
        {{/if}}
    </div>
</body>
</html>
EOF

cat > "$TEMPLATES_DIR/layout.tpl" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ title }}</title>
    <link rel="stylesheet" href="/css/main.css">
</head>
<body>
    <header>
        <nav class="navbar">
            {{ navigation }}
        </nav>
    </header>
    <main>
        {{ content }}
    </main>
    <footer>
        <p>&copy; 2024 {{ siteName }}</p>
    </footer>
</body>
</html>
EOF

# Create simple JS files
cat > "$SRC_DIR/app.js" << 'EOF'
const express = require('express');
const app = express();

app.set('view engine', 'tpl');
app.set('views', './templates');

app.get('/', (req, res) => {
    res.render('home', { 
        pageTitle: 'Home',
        userName: 'User',
        showProducts: true,
        products: [
            { name: 'Product 1', price: 19.99 },
            { name: 'Product 2', price: 29.99 }
        ]
    });
});

app.listen(3000, () => {
    console.log('Server running on port 3000');
});
EOF

cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "template-project",
  "version": "1.0.0",
  "description": "Web project using custom .tpl template files",
  "main": "src/app.js",
  "scripts": {
    "start": "node src/app.js"
  },
  "dependencies": {
    "express": "^4.18.0"
  }
}
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Template Project

This project uses `.tpl` files for HTML templates with embedded template expressions.

## Current Problem

VSCode doesn't recognize `.tpl` files - they show as plain text with no syntax highlighting.
This makes the HTML tags, attributes, and JavaScript code difficult to read and edit.

## Goal

Configure VSCode to treat `.tpl` files as HTML so they display proper syntax highlighting.

## How to Fix

**Option 1 - Settings UI:**
1. Open Settings: Ctrl+, (or Cmd+, on Mac)
2. Search for: "files associations"
3. Click "Add Item"
4. Enter pattern: `*.tpl`
5. Enter language: `html`

**Option 2 - Settings JSON:**
1. Open Command Palette: Ctrl+Shift+P
2. Type: "Preferences: Open Settings (JSON)"
3. Add this to the settings object: