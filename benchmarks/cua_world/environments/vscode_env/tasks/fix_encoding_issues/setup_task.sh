#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Encoding Issues Task ==="

# Install chardet for encoding detection (needed by verifier)
pip install chardet --quiet 2>/dev/null || echo "chardet may already be installed"

WORKSPACE_DIR="/home/ga/workspace/data-pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data" "$WORKSPACE_DIR/docs" "$WORKSPACE_DIR/scripts"

# Create .editorconfig (project standards)
cat > "$WORKSPACE_DIR/.editorconfig" << 'EOF'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
EOF

# Create .gitattributes
cat > "$WORKSPACE_DIR/.gitattributes" << 'EOF'
* text=auto eol=lf
*.sh text eol=lf
*.py text eol=lf
*.md text eol=lf
*.csv text eol=lf
*.txt text eol=lf
EOF

# Create README.md with CRLF line endings (WRONG)
printf "# Data Pipeline Project\r\n\r\nProcessing international customer data.\r\n\r\nSee .editorconfig for project standards.\r\n" > "$WORKSPACE_DIR/README.md"

# Create customers.csv in Windows-1252 encoding (WRONG)
TEMP_CSV=$(mktemp)
cat > "$TEMP_CSV" << 'EOF'
id,name,country
1,José García,Spain
2,François Dupont,France
3,Müller Schmidt,Germany
4,Søren Nielsen,Denmark
EOF
iconv -f UTF-8 -t WINDOWS-1252 < "$TEMP_CSV" > "$WORKSPACE_DIR/data/customers.csv" 2>/dev/null || cp "$TEMP_CSV" "$WORKSPACE_DIR/data/customers.csv"
rm -f "$TEMP_CSV"

# Create locations.txt in ISO-8859-1 encoding (WRONG)
TEMP_LOC=$(mktemp)
cat > "$TEMP_LOC" << 'EOF'
São Paulo, Brazil
Malmö, Sweden
Zürich, Switzerland
Montréal, Canada
EOF
iconv -f UTF-8 -t ISO-8859-1 < "$TEMP_LOC" > "$WORKSPACE_DIR/data/locations.txt" 2>/dev/null || cp "$TEMP_LOC" "$WORKSPACE_DIR/data/locations.txt"
rm -f "$TEMP_LOC"

# Create products.json (CORRECT - UTF-8 with LF) - Control file
cat > "$WORKSPACE_DIR/data/products.json" << 'EOF'
{
  "products": [
    {"id": 1, "name": "Coffee Beans", "price": 12.99},
    {"id": 2, "name": "Tea Leaves", "price": 8.99}
  ]
}
EOF

# Create notes.md with CRLF line endings (WRONG)
printf "# Notes\r\n\r\nImportant observations:\r\n- Data received from Germany office\r\n- Some encoding issues detected\r\n" > "$WORKSPACE_DIR/docs/notes.md"

# Create glossary.txt in ISO-8859-1 encoding (WRONG)
TEMP_GLOS=$(mktemp)
cat > "$TEMP_GLOS" << 'EOF'
Terms to understand:
- naïve: without experience
- café: coffee shop
- résumé: summary of experience
- façade: front of building
EOF
iconv -f UTF-8 -t ISO-8859-1 < "$TEMP_GLOS" > "$WORKSPACE_DIR/docs/glossary.txt" 2>/dev/null || cp "$TEMP_GLOS" "$WORKSPACE_DIR/docs/glossary.txt"
rm -f "$TEMP_GLOS"

# Create process.py (CORRECT - UTF-8 with LF) - Control file
cat > "$WORKSPACE_DIR/scripts/process.py" << 'EOF'
#!/usr/bin/env python3
"""Data processing script"""

def process_data():
    """Process customer data from CSV files"""
    print("Processing data...")
    # TODO: Add processing logic

if __name__ == "__main__":
    process_data()
EOF

# Create validate.sh with CRLF line endings (WRONG)
printf "#!/bin/bash\r\necho \"Validating data files...\"\r\necho \"Checking encoding and format...\"\r\n" > "$WORKSPACE_DIR/scripts/validate.sh"
chmod +x "$WORKSPACE_DIR/scripts/validate.sh"

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initialize git repository
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.email "agent@test.com"
sudo -u ga git config user.name "Test Agent"
sudo -u ga git add -A
sudo -u ga git commit -m "Initial commit with encoding issues" 2>&1 || echo "Git commit failed, continuing..."

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/README.md'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Fix Encoding Issues Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Files with encoding issues (convert to UTF-8):"
echo "    - data/customers.csv"
echo "    - data/locations.txt"
echo "    - docs/glossary.txt"
echo "  Files with line ending issues (convert CRLF to LF):"
echo "    - README.md"
echo "    - docs/notes.md"
echo "    - scripts/validate.sh"
echo ""
echo "  Use status bar indicators (bottom-right) to:"
echo "    1. Change encoding: Click encoding → Reopen with Encoding → Save with Encoding (UTF-8)"
echo "    2. Change line endings: Click CRLF → LF"
echo "  Check .editorconfig for project standards"