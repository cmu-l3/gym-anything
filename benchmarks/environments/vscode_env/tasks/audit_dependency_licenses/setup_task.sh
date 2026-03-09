#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up License Audit Task ==="

PROJECT_DIR="/home/ga/workspace/license_audit_project"
sudo -u ga mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Create package.json with mixed real dependencies
cat > "$PROJECT_DIR/package.json" << 'EOF'
{
  "name": "commercial-analytics-dashboard",
  "version": "2.1.0",
  "description": "Commercial analytics dashboard - proprietary software requiring permissive licenses",
  "private": true,
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.2",
    "lodash": "^4.17.21",
    "axios": "^1.6.0",
    "moment": "^2.29.4",
    "uuid": "^9.0.0",
    "dotenv": "^16.3.1",
    "chalk": "^4.1.2",
    "yargs": "^17.7.2",
    "debug": "^4.3.4",
    "cors": "^2.8.5",
    "body-parser": "^1.20.2",
    "jsonwebtoken": "^9.0.2",
    "bcrypt": "^5.1.1",
    "gpl-problematic-package": "^2.1.0",
    "winston": "^3.11.0"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "eslint": "^8.54.0",
    "nodemon": "^3.0.1"
  },
  "author": "Commercial Corp",
  "license": "PROPRIETARY"
}
EOF

# Create package-lock.json with dependency tree
cat > "$PROJECT_DIR/package-lock.json" << 'EOF'
{
  "name": "commercial-analytics-dashboard",
  "version": "2.1.0",
  "lockfileVersion": 2,
  "requires": true,
  "packages": {
    "": {
      "name": "commercial-analytics-dashboard",
      "version": "2.1.0",
      "license": "PROPRIETARY",
      "dependencies": {
        "express": "^4.18.2",
        "lodash": "^4.17.21",
        "axios": "^1.6.0",
        "moment": "^2.29.4",
        "uuid": "^9.0.0",
        "dotenv": "^16.3.1",
        "chalk": "^4.1.2",
        "yargs": "^17.7.2",
        "debug": "^4.3.4",
        "cors": "^2.8.5",
        "body-parser": "^1.20.2",
        "jsonwebtoken": "^9.0.2",
        "bcrypt": "^5.1.1",
        "gpl-problematic-package": "^2.1.0",
        "winston": "^3.11.0"
      },
      "devDependencies": {
        "jest": "^29.7.0",
        "eslint": "^8.54.0",
        "nodemon": "^3.0.1"
      }
    },
    "node_modules/express": {
      "version": "4.18.2",
      "license": "MIT"
    },
    "node_modules/lodash": {
      "version": "4.17.21",
      "license": "MIT"
    },
    "node_modules/axios": {
      "version": "1.6.0",
      "license": "MIT"
    },
    "node_modules/moment": {
      "version": "2.29.4",
      "license": "MIT"
    },
    "node_modules/uuid": {
      "version": "9.0.0",
      "license": "MIT"
    },
    "node_modules/dotenv": {
      "version": "16.3.1",
      "license": "BSD-2-Clause"
    },
    "node_modules/chalk": {
      "version": "4.1.2",
      "license": "MIT"
    },
    "node_modules/yargs": {
      "version": "17.7.2",
      "license": "MIT"
    },
    "node_modules/debug": {
      "version": "4.3.4",
      "license": "MIT"
    },
    "node_modules/cors": {
      "version": "2.8.5",
      "license": "MIT"
    },
    "node_modules/body-parser": {
      "version": "1.20.2",
      "license": "MIT"
    },
    "node_modules/jsonwebtoken": {
      "version": "9.0.2",
      "license": "MIT"
    },
    "node_modules/bcrypt": {
      "version": "5.1.1",
      "license": "MIT"
    },
    "node_modules/gpl-problematic-package": {
      "version": "2.1.0",
      "license": "GPL-3.0"
    },
    "node_modules/winston": {
      "version": "3.11.0",
      "license": "MIT"
    },
    "node_modules/jest": {
      "version": "29.7.0",
      "license": "MIT",
      "dev": true
    },
    "node_modules/eslint": {
      "version": "8.54.0",
      "license": "MIT",
      "dev": true
    },
    "node_modules/nodemon": {
      "version": "3.0.1",
      "license": "MIT",
      "dev": true
    }
  }
}
EOF

# Create README emphasizing commercial nature
cat > "$PROJECT_DIR/README.md" << 'EOF'
# Commercial Analytics Dashboard

**⚠️ PROPRIETARY SOFTWARE - COMMERCIAL LICENSE**

This is commercial software distributed under a proprietary license.
All dependencies must use permissive open-source licenses compatible with commercial distribution.

## License Compliance Requirements

**APPROVED LICENSES:**
- MIT
- Apache-2.0
- BSD (2-Clause, 3-Clause)
- ISC

**REQUIRES LEGAL REVIEW:**
- LGPL (weak copyleft)
- MPL (Mozilla Public License)
- EPL (Eclipse Public License)

**❌ PROHIBITED LICENSES (Copyleft):**
- GPL (any version)
- AGPL (any version)
- Custom/proprietary licenses from third parties

## Pre-Release Checklist

Before shipping to customers, legal team requires:
1. Complete dependency license audit
2. Identification of any copyleft licenses
3. Plan to replace or remove incompatible dependencies
4. Documentation of license compliance

**URGENT:** Release scheduled in 48 hours. Need license audit ASAP!
EOF

# Create node_modules directory structure
sudo -u ga mkdir -p "$PROJECT_DIR/node_modules"

# Create the problematic GPL package directory with LICENSE file
sudo -u ga mkdir -p "$PROJECT_DIR/node_modules/gpl-problematic-package"

cat > "$PROJECT_DIR/node_modules/gpl-problematic-package/package.json" << 'EOF'
{
  "name": "gpl-problematic-package",
  "version": "2.1.0",
  "description": "A package with GPL license (problematic for commercial use)",
  "main": "index.js",
  "license": "GPL-3.0",
  "author": "Open Source Developer"
}
EOF

cat > "$PROJECT_DIR/node_modules/gpl-problematic-package/LICENSE" << 'EOF'
GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007

Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
EOF

cat > "$PROJECT_DIR/node_modules/gpl-problematic-package/README.md" << 'EOF'
# GPL Problematic Package

This package is licensed under GPL-3.0, which is a strong copyleft license.

⚠️ **Warning**: This license is incompatible with proprietary/commercial software distribution.
EOF

# Create a few more realistic package directories (MIT licensed)
sudo -u ga mkdir -p "$PROJECT_DIR/node_modules/express"
cat > "$PROJECT_DIR/node_modules/express/package.json" << 'EOF'
{
  "name": "express",
  "version": "4.18.2",
  "description": "Fast, unopinionated, minimalist web framework",
  "license": "MIT"
}
EOF

sudo -u ga mkdir -p "$PROJECT_DIR/node_modules/lodash"
cat > "$PROJECT_DIR/node_modules/lodash/package.json" << 'EOF'
{
  "name": "lodash",
  "version": "4.17.21",
  "description": "Lodash modular utilities",
  "license": "MIT"
}
EOF

sudo -u ga mkdir -p "$PROJECT_DIR/node_modules/axios"
cat > "$PROJECT_DIR/node_modules/axios/package.json" << 'EOF'
{
  "name": "axios",
  "version": "1.6.0",
  "description": "Promise based HTTP client",
  "license": "MIT"
}
EOF

# Create a package with missing license info
sudo -u ga mkdir -p "$PROJECT_DIR/node_modules/unlicensed-helper"
cat > "$PROJECT_DIR/node_modules/unlicensed-helper/package.json" << 'EOF'
{
  "name": "unlicensed-helper",
  "version": "1.0.0",
  "description": "Helper utilities with unclear licensing"
}
EOF

# Add unlicensed-helper to package.json dependencies
cat > "$PROJECT_DIR/package.json" << 'EOF'
{
  "name": "commercial-analytics-dashboard",
  "version": "2.1.0",
  "description": "Commercial analytics dashboard - proprietary software requiring permissive licenses",
  "private": true,
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.2",
    "lodash": "^4.17.21",
    "axios": "^1.6.0",
    "moment": "^2.29.4",
    "uuid": "^9.0.0",
    "dotenv": "^16.3.1",
    "chalk": "^4.1.2",
    "yargs": "^17.7.2",
    "debug": "^4.3.4",
    "cors": "^2.8.5",
    "body-parser": "^1.20.2",
    "jsonwebtoken": "^9.0.2",
    "bcrypt": "^5.1.1",
    "gpl-problematic-package": "^2.1.0",
    "unlicensed-helper": "^1.0.0",
    "winston": "^3.11.0"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "eslint": "^8.54.0",
    "nodemon": "^3.0.1"
  },
  "author": "Commercial Corp",
  "license": "PROPRIETARY"
}
EOF

# Fix ownership
sudo chown -R ga:ga "$PROJECT_DIR"

# Open VSCode to the project
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$PROJECT_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open README to set context
su - ga -c "DISPLAY=:1 code '$PROJECT_DIR/README.md'" &
sleep 2

echo "=== License Audit Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review package.json to see project dependencies"
echo "  2. Examine package-lock.json for full dependency tree"
echo "  3. Check node_modules directories for LICENSE files"
echo "  4. Identify dependencies with problematic licenses (GPL, AGPL)"
echo "  5. Check for dependencies with missing license information"
echo "  6. Create LICENSE_AUDIT_REPORT.md in project root"
echo "  7. Document all findings with risk levels and recommendations"
echo ""
echo "⚠️  CRITICAL: This is commercial software. GPL licenses are incompatible!"