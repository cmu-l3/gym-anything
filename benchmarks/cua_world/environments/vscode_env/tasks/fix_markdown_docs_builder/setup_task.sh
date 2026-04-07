#!/bin/bash
set -e
echo "=== Setting up Fix Markdown Docs Builder Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

WORKSPACE="/home/ga/workspace/docs_builder"
sudo -u ga mkdir -p "$WORKSPACE/src"
sudo -u ga mkdir -p "$WORKSPACE/docs/advanced"

# Write package.json
sudo -u ga cat > "$WORKSPACE/package.json" << 'EOF'
{
  "name": "docs-builder",
  "version": "1.0.0",
  "description": "Custom Markdown Builder",
  "scripts": {
    "build": "node src/index.js"
  }
}
EOF

# Write src/index.js (Bug 1: Async race condition)
sudo -u ga cat > "$WORKSPACE/src/index.js" << 'EOF'
const fs = require('fs').promises;
const path = require('path');
const { parseMarkdown } = require('./parser');
const { validateLinks } = require('./validator');
const { copyAssets } = require('./assets');

async function walk(dir) {
    let results = [];
    const list = await fs.readdir(dir);
    for (let file of list) {
        file = path.join(dir, file);
        const stat = await fs.stat(file);
        if (stat && stat.isDirectory()) {
            if (!file.endsWith('assets')) {
                results = results.concat(await walk(file));
            }
        } else if (file.endsWith('.md')) {
            results.push(file);
        }
    }
    return results;
}

async function build() {
    console.log('Starting build...');
    await fs.mkdir('dist', { recursive: true });
    const files = await walk('docs');
    const fileMap = new Set();

    // BUG 1: Async race condition. forEach does not await the inner async functions.
    files.forEach(async (file) => {
        const content = await fs.readFile(file, 'utf-8');
        const parsed = parseMarkdown(content, file);
        const outPath = file.replace('docs/', 'dist/').replace('.md', '.html');
        await fs.mkdir(path.dirname(outPath), { recursive: true });
        await fs.writeFile(outPath, parsed.html);
        fileMap.add(outPath.replace('dist/', ''));
    });

    // A tiny delay so the script doesn't completely crash, but it will miss files
    await new Promise(r => setTimeout(r, 10));

    await validateLinks(fileMap);
    await copyAssets();
    console.log('Build complete!');
}

build().catch(console.error);
EOF

# Write src/parser.js (Bug 2: Greedy Regex, Bug 3: Missing global flag)
sudo -u ga cat > "$WORKSPACE/src/parser.js" << 'EOF'
const { getAssetPath } = require('./assets');

function parseMarkdown(content, filePath) {
    // BUG 2: Greedy regex swallows content if multiple horizontal rules exist
    const fmRegex = /^---\n([\s\S]*)\n---/m;
    const match = content.match(fmRegex);
    let body = content;
    if (match) {
        body = content.replace(match[0], '');
    }

    // Add logo image at the top
    let html = `<img src="${getAssetPath(filePath)}" alt="Logo">\n`;

    // Parse wiki links e.g. [[Page Name]]
    // BUG 3: Missing global 'g' flag, only parses the first link per block
    const wikiRegex = /\[\[(.*?)\]\]/;
    body = body.replace(wikiRegex, (m, p1) => {
        return `<a href="${encodeURI(p1)}.html">${p1}</a>`;
    });

    // Convert basic markdown tags
    body = body.replace(/^# (.*$)/gim, '<h1>$1</h1>');
    body = body.replace(/\n\n/g, '<br><br>');

    html += body.trim();
    return { html };
}

module.exports = { parseMarkdown };
EOF

# Write src/validator.js (Bug 4: Missing URL Decoding)
sudo -u ga cat > "$WORKSPACE/src/validator.js" << 'EOF'
const fs = require('fs').promises;
const path = require('path');

async function validateLinks(fileMap) {
    console.log("Validating internal links...");
    let deadLinks = 0;

    for (const file of fileMap) {
        try {
            const content = await fs.readFile(path.join('dist', file), 'utf-8');
            const hrefs = [...content.matchAll(/<a href="([^"]+)">/g)].map(m => m[1]);

            for (const href of hrefs) {
                if (href.startsWith('http')) continue;

                // BUG 4: The href is URL-encoded (e.g., getting%20started.html)
                // but fileMap contains unencoded filenames. Missing decodeURIComponent!
                const target = href;

                if (!fileMap.has(target)) {
                    console.error(`DEAD LINK in ${file}: ${target}`);
                    deadLinks++;
                }
            }
        } catch (err) {
            // File might not exist due to async bug
        }
    }

    if (deadLinks > 0) {
        console.error(`Validation failed with ${deadLinks} dead links.`);
    } else {
        console.log("All links are valid.");
    }
}

module.exports = { validateLinks };
EOF

# Write src/assets.js (Bug 5: Incorrect Depth Calculation)
sudo -u ga cat > "$WORKSPACE/src/assets.js" << 'EOF'
const fs = require('fs').promises;

async function copyAssets() {
    await fs.mkdir('dist/assets', { recursive: true });
    await fs.writeFile('dist/assets/logo.png', 'fake-image-data');
}

function getAssetPath(filePath) {
    // Compute relative path to the root assets folder
    const parts = filePath.split('/');
    
    // BUG 5: This includes the 'docs/' root in the depth count
    const depth = parts.length - 1;

    if (depth === 1) {
        return './assets/logo.png';
    }
    const prefix = '../'.repeat(depth);
    return `${prefix}assets/logo.png`;
}

module.exports = { copyAssets, getAssetPath };
EOF

# Create Documentation Markdown Corpus
sudo -u ga cat > "$WORKSPACE/docs/index.md" << 'EOF'
---
title: Home
---
# Welcome to the Docs
Please see [[getting started]] for more information.
EOF

sudo -u ga cat > "$WORKSPACE/docs/getting started.md" << 'EOF'
---
title: Getting Started
---
# Getting Started
This is the getting started guide.
Check out advanced topics like [[advanced/routing]].
EOF

sudo -u ga cat > "$WORKSPACE/docs/advanced/routing.md" << 'EOF'
---
title: Routing
---
# Routing
Routing is complex. See [[advanced/middleware]].
EOF

sudo -u ga cat > "$WORKSPACE/docs/advanced/middleware.md" << 'EOF'
---
title: Middleware
---
# Middleware
Read about [[advanced/routing]] and [[getting started]].

---
This is an important note after a horizontal rule.
EOF

# Launch VS Code pointing to the workspace
echo "Launching VSCode..."
sudo -u ga code "$WORKSPACE"
sleep 5

# Ensure VSCode is maximized and focused
wait_for_vscode 30 || true
focus_vscode_window 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="