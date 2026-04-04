#!/bin/bash
# Setup script for Install eForm Template task
set -e

echo "=== Setting up Install eForm Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Wait for OSCAR to be ready
wait_for_oscar_http 300

# 3. Create the eForm HTML file in Documents
# We embed a unique string 'RPA_2024_SECURE_CHECK' to verify the correct file was uploaded
echo "Creating eForm template file..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/pain_assessment.html <<EOF
<html>
<!-- Oscar eForm Template: Rapid Pain Assessment -->
<head>
<title>Rapid Pain Assessment</title>
<style>
  body { font-family: sans-serif; padding: 20px; background-color: #f9f9f9; }
  .header { border-bottom: 2px solid #003366; margin-bottom: 20px; color: #003366; }
  .field { margin: 15px 0; padding: 10px; background: white; border: 1px solid #ddd; }
  label { font-weight: bold; display: block; margin-bottom: 5px; }
  input[type="text"], textarea { width: 100%; padding: 5px; }
  .footer { font-size: 0.8em; color: #666; margin-top: 30px; border-top: 1px solid #ccc; padding-top: 10px; }
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <h1>Rapid Pain Assessment Tool</h1>
    <p>Clinic Internal Use Only - v1.0</p>
  </div>
  
  <form>
    <!-- Database Mappings -->
    <div class="field">
      <label>Patient Name:</label>
      <input type="text" name="patient_name" oscarDB="patient_name" readonly style="background-color: #eee;">
    </div>
    
    <div class="field">
      <label>Date of Assessment:</label>
      <input type="text" name="visit_date" oscarDB="today">
    </div>
    
    <hr>
    
    <!-- Clinical Data -->
    <div class="field">
      <label>Current Pain Level (0-10):</label>
      <select name="pain_score">
        <option value="">-- Select --</option>
        <option value="0">0 - No Pain</option>
        <option value="1">1</option>
        <option value="2">2</option>
        <option value="3">3</option>
        <option value="4">4</option>
        <option value="5">5 - Moderate</option>
        <option value="6">6</option>
        <option value="7">7</option>
        <option value="8">8</option>
        <option value="9">9</option>
        <option value="10">10 - Worst Possible</option>
      </select>
    </div>
    
    <div class="field">
      <label>Pain Location:</label>
      <input type="text" name="pain_location" placeholder="e.g. Lower back, Left knee">
    </div>
    
    <div class="field">
      <label>Description / Character:</label>
      <textarea name="pain_desc" rows="3" placeholder="e.g. Sharp, throbbing, dull ache"></textarea>
    </div>
    
    <div class="field">
      <label>Flags:</label>
      <input type="checkbox" name="red_flags"> <b>Red Flags Present</b> (Requires immediate physician review)
    </div>
    
    <!-- Verification Token (Hidden from user view but present in source) -->
    <!-- RPA_2024_SECURE_CHECK -->
    
    <div class="footer">
      <input type="button" value="Print Form" onclick="window.print();">
      <input type="button" value="Submit" onclick="submitForm();">
    </div>
  </form>
</div>
<script>
  function submitForm() { alert('Form saved to chart.'); }
</script>
</body>
</html>
EOF

# Set permissions so ga user can read it
chmod 644 /home/ga/Documents/pain_assessment.html
chown ga:ga /home/ga/Documents/pain_assessment.html
echo "File created at /home/ga/Documents/pain_assessment.html"

# 4. Clean up any previous attempts (Idempotency)
# We delete any eForm with this specific name to ensure a clean state
echo "Cleaning up any existing 'Rapid Pain Assessment' forms..."
oscar_query "DELETE FROM eform WHERE form_name='Rapid Pain Assessment'" 2>/dev/null || true

# 5. Record initial count for anti-gaming verification
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM eform" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_eform_count.txt
echo "Initial eForm count: $INITIAL_COUNT"

# 6. Launch Firefox on Login Page
ensure_firefox_on_oscar

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="