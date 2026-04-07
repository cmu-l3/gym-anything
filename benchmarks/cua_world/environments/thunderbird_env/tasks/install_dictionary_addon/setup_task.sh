#!/bin/bash
echo "=== Setting up install_dictionary_addon task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Generate a valid minimal Thunderbird Dictionary XPI using Python
# (This ensures the extension works offline without needing external downloads)
python3 -c "
import zipfile
import os

os.makedirs('/tmp/es_dict/dictionaries', exist_ok=True)

# Create manifest.json
with open('/tmp/es_dict/manifest.json', 'w') as f:
    f.write('''{
  \"manifest_version\": 2,
  \"name\": \"Spanish (Spain) Dictionary\",
  \"version\": \"1.0\",
  \"applications\": {
    \"gecko\": {
      \"id\": \"es-es@dictionaries.addons.mozilla.org\",
      \"strict_min_version\": \"60.0\"
    }
  },
  \"dictionaries\": {
    \"es-ES\": \"dictionaries/es-ES.dic\"
  }
}''')

# Create mock dictionary files
with open('/tmp/es_dict/dictionaries/es-ES.dic', 'w') as f:
    f.write('1\\nHola\\n')
with open('/tmp/es_dict/dictionaries/es-ES.aff', 'w') as f:
    f.write('SET UTF-8\\n')
    
# Zip it up as an XPI file
os.makedirs('/home/ga/Downloads', exist_ok=True)
with zipfile.ZipFile('/home/ga/Downloads/es-ES-dictionary.xpi', 'w') as zf:
    zf.write('/tmp/es_dict/manifest.json', 'manifest.json')
    zf.write('/tmp/es_dict/dictionaries/es-ES.dic', 'dictionaries/es-ES.dic')
    zf.write('/tmp/es_dict/dictionaries/es-ES.aff', 'dictionaries/es-ES.aff')
"

chown ga:ga /home/ga/Downloads/es-ES-dictionary.xpi
chmod 644 /home/ga/Downloads/es-ES-dictionary.xpi

# Ensure Thunderbird is running
start_thunderbird

# Wait for Thunderbird window to appear
wait_for_thunderbird_window 30
sleep 3

# Maximize Thunderbird window
maximize_thunderbird

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="