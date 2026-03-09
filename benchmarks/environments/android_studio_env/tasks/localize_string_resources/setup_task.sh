#!/bin/bash
set -e

echo "=== Setting up localize_string_resources task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="NoteKeeper"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="app/src/main/java/com/example/notekeeper"

# Clean up previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
mkdir -p "$PROJECT_DIR"

echo "Generating minimal Android project structure..."

# Create directory structure
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/res/drawable"
mkdir -p "$PROJECT_DIR/$PACKAGE_DIR"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 1. Settings Gradle
cat > "$PROJECT_DIR/settings.gradle.kts" <<EOF
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "$PROJECT_NAME"
include(":app")
EOF

# 2. Top-level Build Gradle
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# 3. App Build Gradle
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.notekeeper"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.notekeeper"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
}
EOF

# 4. Android Manifest
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.NoteKeeper"
        tools:targetApi="31">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
EOF

# 5. Create dummy xml rules to satisfy manifest
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo "<data-extraction-rules></data-extraction-rules>" > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
echo "<full-backup-content></full-backup-content>" > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"

# 6. Dummy Main Activity
cat > "$PROJECT_DIR/$PACKAGE_DIR/MainActivity.kt" <<EOF
package com.example.notekeeper

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# 7. Dummy Layout
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/title_home" />
</LinearLayout>
EOF

# 8. Colors and Themes
cat > "$PROJECT_DIR/app/src/main/res/values/colors.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="black">#FF000000</color>
    <color name="white">#FFFFFFFF</color>
</resources>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" <<EOF
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.NoteKeeper" parent="Theme.Material3.DayNight.NoActionBar">
        <!-- Customize your light theme here. -->
    </style>
    <style name="Theme.NoteKeeper" parent="Base.Theme.NoteKeeper" />
</resources>
EOF

# 9. REQUIRED ENGLISH STRINGS (The starting point)
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" <<EOF
<resources>
    <string name="app_name">NoteKeeper</string>
    <string name="title_home">Home</string>
    <string name="title_notes">My Notes</string>
    <string name="title_settings">Settings</string>
    <string name="action_add_note">Add Note</string>
    <string name="action_delete">Delete</string>
    <string name="action_save">Save</string>
    <string name="action_cancel">Cancel</string>
    <string name="hint_note_title">Enter note title</string>
    <string name="hint_note_content">Write your note here</string>
    <string name="msg_note_saved">Note saved successfully</string>
    <string name="msg_note_deleted">Note deleted</string>
    <string name="msg_no_notes">No notes yet. Tap + to create one.</string>
    <string name="dialog_delete_title">Delete Note</string>
    <string name="dialog_delete_message">Are you sure you want to delete this note? This action cannot be undone.</string>
</resources>
EOF

# 10. Copy Gradle Wrapper from a system source or create a minimal one
# Since we might not have a clean wrapper source, we'll try to use the system gradle if wrapper fails,
# but for Android Studio it's best to have a wrapper. We will copy from /opt/android-studio/plugins/android/lib/templates if possible,
# or just rely on Android Studio generating it on import.
# However, to be safe for CLI building in export, we'll try to `gradle wrapper` if gradle is in path.
if command -v gradle >/dev/null 2>&1; then
    cd "$PROJECT_DIR"
    gradle wrapper --gradle-version 8.4 >/dev/null 2>&1 || true
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
if [ -f "$PROJECT_DIR/gradlew" ]; then
    chmod +x "$PROJECT_DIR/gradlew"
fi

# Open Android Studio
echo "Opening project in Android Studio..."
setup_android_studio_project "$PROJECT_DIR" "NoteKeeper" 180

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="