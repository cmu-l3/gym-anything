#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Add License Headers Task ==="

WORKSPACE_DIR="/home/ga/workspace/data-transformer"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{src/{utils,parsers,transformers},tests,.templates}

# Create Python files WITHOUT headers
cat > "$WORKSPACE_DIR/src/main.py" << 'EOF'
#!/usr/bin/env python3
"""Main entry point for data-transformer CLI."""

import sys
from utils.logger import setup_logging
from parsers.json_parser import JSONParser

def main():
    setup_logging()
    parser = JSONParser()
    # ... implementation
    
if __name__ == "__main__":
    main()
EOF

cat > "$WORKSPACE_DIR/src/utils/logger.py" << 'EOF'
"""Logging configuration module."""
import logging

def setup_logging(level=logging.INFO):
    logging.basicConfig(level=level)
    return logging.getLogger(__name__)
EOF

cat > "$WORKSPACE_DIR/src/parsers/json_parser.py" << 'EOF'
import json
from typing import Dict, Any

class JSONParser:
    """Parse and validate JSON data."""
    
    def parse(self, data: str) -> Dict[str, Any]:
        return json.loads(data)
EOF

# Create JavaScript files WITHOUT headers
cat > "$WORKSPACE_DIR/src/transformers/mapper.js" << 'EOF'
const { validateSchema } = require('./validator');

class DataMapper {
  constructor(config) {
    this.config = config;
  }
  
  transform(input) {
    return validateSchema(input, this.config);
  }
}

module.exports = { DataMapper };
EOF

cat > "$WORKSPACE_DIR/src/transformers/validator.js" << 'EOF'
function validateSchema(data, schema) {
  // Validation logic
  return data;
}

module.exports = { validateSchema };
EOF

# Create TypeScript file WITHOUT header
cat > "$WORKSPACE_DIR/src/types.ts" << 'EOF'
export interface TransformConfig {
  source: string;
  target: string;
  rules: Record<string, unknown>;
}

export type ValidationResult = {
  valid: boolean;
  errors: string[];
};
EOF

# Create one file that ALREADY has a license (should be skipped)
cat > "$WORKSPACE_DIR/src/utils/config.py" << 'EOF'
# Copyright (c) 2024 DataTransformer Contributors
# SPDX-License-Identifier: MIT
"""Configuration management."""

import os
from pathlib import Path

def load_config():
    return {}
EOF

# Create files in excluded directories (should be skipped)
cat > "$WORKSPACE_DIR/tests/test_parser.py" << 'EOF'
import unittest
from src.parsers.json_parser import JSONParser

class TestParser(unittest.TestCase):
    def test_basic(self):
        pass
EOF

sudo -u ga mkdir -p "$WORKSPACE_DIR/node_modules/lodash"
echo "module.exports = {}" > "$WORKSPACE_DIR/node_modules/lodash/index.js"

# Create reference header template files
cat > "$WORKSPACE_DIR/.templates/license_header_python.txt" << 'EOF'
# Copyright (c) 2024 DataTransformer Contributors
# SPDX-License-Identifier: MIT
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
EOF

cat > "$WORKSPACE_DIR/.templates/license_header_js.txt" << 'EOF'
// Copyright (c) 2024 DataTransformer Contributors
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
EOF

# Set proper ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open workspace in VSCode
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Add License Headers Task Setup Complete ==="
echo "📝 Workspace: $WORKSPACE_DIR"
echo ""
echo "Files needing headers (6 files):"
echo "  - src/main.py (has shebang - header goes AFTER it)"
echo "  - src/utils/logger.py"
echo "  - src/parsers/json_parser.py"
echo "  - src/transformers/mapper.js"
echo "  - src/transformers/validator.js"
echo "  - src/types.ts"
echo ""
echo "Files to skip:"
echo "  - src/utils/config.py (already has license)"
echo "  - tests/* (excluded directory)"
echo "  - node_modules/* (excluded directory)"
echo ""
echo "Template files available at:"
echo "  - .templates/license_header_python.txt"
echo "  - .templates/license_header_js.txt"