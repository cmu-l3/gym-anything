#!/bin/bash
echo "=== Setting up debug_runtime_crash task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Clean up any previous task artifacts
rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log /tmp/original_hashes.txt 2>/dev/null || true

# Project paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/NotepadApp"
DATA_SOURCE="/workspace/data/NotepadApp"
PKG_PATH="com/example/notepad"

# Remove any existing NotepadApp project so we start fresh
rm -rf "$PROJECT_DIR" 2>/dev/null || true

# Copy NotepadApp from data directory to user's project space
mkdir -p /home/ga/AndroidStudioProjects
cp -r "$DATA_SOURCE" "$PROJECT_DIR"

# Set ownership and permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;

# Make gradlew executable
chmod +x "$PROJECT_DIR/gradlew"

SRC_DIR="$PROJECT_DIR/app/src/main/java/$PKG_PATH"

# =============================================
# BUG 1: NotepadActivity.kt — remove formatter/validator initialization
# Change "private val formatter = NoteFormatter()" to "private lateinit var formatter: NoteFormatter"
# and "private val validator = NoteValidator()" to "private lateinit var validator: NoteValidator"
# but do NOT add initialization in onCreate — causes UninitializedPropertyAccessException
# =============================================
echo "Planting Bug 1: lateinit without initialization..."
sed -i 's/private val validator = NoteValidator()/private lateinit var validator: NoteValidator/' "$SRC_DIR/NotepadActivity.kt"
sed -i 's/private val formatter = NoteFormatter()/private lateinit var formatter: NoteFormatter/' "$SRC_DIR/NotepadActivity.kt"

# =============================================
# BUG 2: NoteFormatter.kt — formatPreview crashes on short content
# Add an unsafe substring(0, maxLength) call BEFORE the length check
# This always runs, so short content triggers StringIndexOutOfBoundsException
# =============================================
echo "Planting Bug 2: unsafe substring in formatPreview..."
python3 << 'BUG2_EOF'
import sys

path = sys.argv[1] if len(sys.argv) > 1 else None
BUG2_EOF

# Use a python script file to avoid bash escaping issues
cat > /tmp/plant_bug2.py << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

old = '        return if (singleLine.length > maxLength) {\n            "${singleLine.take(maxLength)}..."\n        } else {\n            singleLine\n        }'

new = '        val truncated = singleLine.substring(0, maxLength)\n        return if (singleLine.length > maxLength) {\n            truncated + "..."\n        } else {\n            singleLine\n        }'

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('Bug 2 planted: unsafe substring in formatPreview')
else:
    print('ERROR: Bug 2 pattern not found in NoteFormatter.kt')
    sys.exit(1)
PYEOF
python3 /tmp/plant_bug2.py "$SRC_DIR/NoteFormatter.kt"

# =============================================
# BUG 3: NoteValidator.kt — isNoteComplete infinite recursion
# Replace the final 'return true' with 'return isNoteComplete(note)'
# This causes a StackOverflowError
# =============================================
echo "Planting Bug 3: isNoteComplete recursive call..."
cat > /tmp/plant_bug3.py << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

old = '    fun isNoteComplete(note: Note): Boolean {\n        if (!isValidTitle(note.title)) return false\n        if (!isValidContent(note.content)) return false\n        if (note.content.isBlank()) return false\n        return true\n    }'

new = '    fun isNoteComplete(note: Note): Boolean {\n        if (!isValidTitle(note.title)) return false\n        if (!isValidContent(note.content)) return false\n        if (note.content.isBlank()) return false\n        // Also validate the full note object\n        return isNoteComplete(note)\n    }'

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('Bug 3 planted: isNoteComplete recursive call')
else:
    print('ERROR: Bug 3 pattern not found in NoteValidator.kt')
    sys.exit(1)
PYEOF
python3 /tmp/plant_bug3.py "$SRC_DIR/NoteValidator.kt"

# =============================================
# BUG 4: Note.kt — charCount crashes with NumberFormatException
# Replace the working charCount with a broken version that concatenates
# the cleaned length with the color int and tries to parse it
# =============================================
echo "Planting Bug 4: charCount NumberFormatException..."
cat > /tmp/plant_bug4.py << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

old = '    fun charCount(): Int {\n        return content.replace("\\\\s".toRegex(), "").length\n    }'

new = '    fun charCount(): Int {\n        val cleaned = content.replace("\\\\s".toRegex(), "")\n        return Integer.parseInt(cleaned.length.toString() + color.toString())\n    }'

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('Bug 4 planted: charCount NumberFormatException')
else:
    print('ERROR: Bug 4 pattern not found in Note.kt')
    sys.exit(1)
PYEOF
python3 /tmp/plant_bug4.py "$SRC_DIR/Note.kt"

# Record file hashes of the broken versions (for integrity check to confirm changes were made)
{
    echo "ORIG_ACTIVITY_HASH=$(md5sum "$SRC_DIR/NotepadActivity.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_FORMATTER_HASH=$(md5sum "$SRC_DIR/NoteFormatter.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_VALIDATOR_HASH=$(md5sum "$SRC_DIR/NoteValidator.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_NOTE_HASH=$(md5sum "$SRC_DIR/Note.kt" 2>/dev/null | awk '{print $1}')"
} > /tmp/original_hashes.txt

echo "Original (broken) file hashes recorded:"
cat /tmp/original_hashes.txt

# Verify the project still compiles (bugs are runtime, not compile-time)
echo "Verifying broken project still compiles..."
cd "$PROJECT_DIR"
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
ANDROID_SDK_ROOT=/opt/android-sdk \
ANDROID_HOME=/opt/android-sdk \
./gradlew compileDebugKotlin --no-daemon > /tmp/compile_check.log 2>&1
if [ $? -eq 0 ]; then
    echo "Project compiles (bugs are runtime-only) - good"
else
    echo "WARNING: Project has compile errors - bugs may be too aggressive"
    tail -20 /tmp/compile_check.log
fi

date +%s > /tmp/task_start_timestamp

# Open the project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "NotepadApp" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
