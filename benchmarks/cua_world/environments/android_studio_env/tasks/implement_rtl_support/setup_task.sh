#!/bin/bash
echo "=== Setting up implement_rtl_support task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -rf /tmp/task_result.json /tmp/gradle_output.log 2>/dev/null || true

# ------------------------------------------------------------------
# 1. Prepare the GlobalNews Project
# We base this on the SunflowerApp template but modify it to look like a legacy app
# ------------------------------------------------------------------
PROJECT_DIR="/home/ga/AndroidStudioProjects/GlobalNews"
TEMPLATE_SOURCE="/workspace/data/SunflowerApp"

# Clean up existing project
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p /home/ga/AndroidStudioProjects

# Copy template to new project name
echo "Creating GlobalNews project from template..."
if [ -d "$TEMPLATE_SOURCE" ]; then
    cp -r "$TEMPLATE_SOURCE" "$PROJECT_DIR"
else
    # Fallback if template missing (should not happen in this env)
    echo "ERROR: Template source not found at $TEMPLATE_SOURCE"
    exit 1
fi

# ------------------------------------------------------------------
# 2. Inject "Legacy" State (No RTL, Absolute Positioning)
# ------------------------------------------------------------------

# Modify AndroidManifest.xml: Remove supportsRtl if exists, or set to false
MANIFEST_FILE="$PROJECT_DIR/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST_FILE" ]; then
    # Remove existing supportsRtl attribute
    sed -i 's/android:supportsRtl="true"//g' "$MANIFEST_FILE"
    sed -i 's/android:supportsRtl="false"//g' "$MANIFEST_FILE"
    # Ensure it's not there (sed might leave holes, but that's fine for XML)
fi

# Create the specific legacy layout file: activity_profile.xml
LAYOUT_DIR="$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$LAYOUT_DIR"
LAYOUT_FILE="$LAYOUT_DIR/activity_profile.xml"

# Create a layout full of legacy attributes
cat > "$LAYOUT_FILE" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:paddingLeft="16dp"
    android:paddingRight="16dp"
    android:paddingTop="16dp"
    android:paddingBottom="16dp">

    <ImageView
        android:id="@+id/avatar"
        android:layout_width="80dp"
        android:layout_height="80dp"
        android:layout_alignParentLeft="true"
        android:layout_marginRight="16dp"
        android:src="@drawable/ic_launcher_foreground" />

    <TextView
        android:id="@+id/username"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_toRightOf="@id/avatar"
        android:text="John Doe"
        android:textSize="20sp"
        android:gravity="left" />

    <TextView
        android:id="@+id/bio"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_below="@id/username"
        android:layout_toRightOf="@id/avatar"
        android:layout_marginTop="8dp"
        android:layout_marginLeft="0dp"
        android:text="Global News Reader" />

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_below="@id/avatar"
        android:layout_marginTop="24dp"
        android:orientation="horizontal">

        <TextView
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:gravity="center_horizontal"
            android:text="Posts" />

        <TextView
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:paddingLeft="10dp"
            android:paddingRight="10dp"
            android:gravity="right"
            android:text="Followers" />
    </LinearLayout>

</RelativeLayout>
EOF

# Ensure dummy drawable exists so build doesn't fail on missing resource
# (Sunflower usually has ic_launcher_foreground, but let's be safe)
# If not present, we remove the src attribute to prevent build error
if ! grep -q "ic_launcher_foreground" "$PROJECT_DIR/app/src/main/res/drawable" 2>/dev/null; then
    # It's usually in mipmap-anydpi-v26, but let's assume standard template.
    # We'll just leave it; usually standard templates have it.
    true
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# ------------------------------------------------------------------
# 3. Setup Android Studio
# ------------------------------------------------------------------
setup_android_studio_project "$PROJECT_DIR" "GlobalNews" 120

# Open the specific file to help the agent
echo "Opening activity_profile.xml..."
su - ga -c "DISPLAY=:1 /opt/android-studio/bin/studio.sh '$LAYOUT_FILE' > /dev/null 2>&1 &"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="