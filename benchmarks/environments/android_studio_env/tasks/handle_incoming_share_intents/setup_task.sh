#!/bin/bash
set -e
echo "=== Setting up Handle Incoming Share Intents task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous run
rm -rf /tmp/task_result.json 2>/dev/null || true
rm -rf /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -rf /tmp/gradle_build_output.log 2>/dev/null || true

# Define paths
PROJECT_NAME="SimpleNotes"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"

# Remove existing project if any
rm -rf "$PROJECT_DIR" 2>/dev/null || true

# Create Project Directory Structure
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/simplenotes"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

echo "Creating project files..."

# 1. Create Build Files (Kotlin DSL)
# Root build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

# Settings.gradle.kts
cat > "$PROJECT_DIR/settings.gradle.kts" << 'EOF'
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
rootProject.name = "SimpleNotes"
include(":app")
EOF

# App build.gradle.kts
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.simplenotes"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.simplenotes"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
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
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
EOF

# 2. Create Manifest (Initial state: no intent filter)
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
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
        android:theme="@style/Theme.SimpleNotes"
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

# 3. Create Resources
# Layout
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:padding="16dp"
    tools:context=".MainActivity">

    <EditText
        android:id="@+id/noteInput"
        android:layout_width="0dp"
        android:layout_height="0dp"
        android:layout_marginBottom="16dp"
        android:background="@android:drawable/edit_text"
        android:gravity="top|start"
        android:hint="Type your note here..."
        android:inputType="textMultiLine"
        app:layout_constraintBottom_toTopOf="@+id/saveButton"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

    <Button
        android:id="@+id/saveButton"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Save Note"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# Strings
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">SimpleNotes</string>
</resources>
EOF

# Themes
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'EOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.SimpleNotes" parent="Theme.Material3.DayNight.NoActionBar">
        <item name="colorPrimary">@color/purple_500</item>
    </style>
    <style name="Theme.SimpleNotes" parent="Base.Theme.SimpleNotes" />
</resources>
EOF

# Colors
cat > "$PROJECT_DIR/app/src/main/res/values/colors.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="purple_200">#FFBB86FC</color>
    <color name="purple_500">#FF6200EE</color>
    <color name="purple_700">#FF3700B3</color>
    <color name="teal_200">#FF03DAC5</color>
    <color name="teal_700">#FF018786</color>
    <color name="black">#FF000000</color>
    <color name="white">#FFFFFFFF</color>
</resources>
EOF

# XML Rules (Backup)
echo '<data-extraction-rules></data-extraction-rules>' > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
echo '<full-backup-content></full-backup-content>' > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"

# 4. Create Source Code (Initial state: no handling logic)
cat > "$PROJECT_DIR/app/src/main/java/com/example/simplenotes/MainActivity.kt" << 'EOF'
package com.example.simplenotes

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private lateinit var noteInput: EditText
    private lateinit var saveButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        noteInput = findViewById(R.id.noteInput)
        saveButton = findViewById(R.id.saveButton)

        saveButton.setOnClickListener {
            Toast.makeText(this, "Note saved (Simulation)", Toast.LENGTH_SHORT).show()
            noteInput.text.clear()
        }

        // TODO: Handle incoming shared text here
    }
}
EOF

# 5. Gradle Wrapper Setup
# Attempt to copy from studio installation or download/generate
if [ -d "/opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradle" ]; then
    cp -r /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradle/ "$PROJECT_DIR/gradle/wrapper/"
    cp /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew "$PROJECT_DIR/"
    cp /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew.bat "$PROJECT_DIR/"
else
    # Minimal fallback or rely on IDE to generate
    echo "Creating minimal gradle wrapper structure..."
    mkdir -p "$PROJECT_DIR/gradle/wrapper"
    # We assume the environment has valid gradle wrapper or IDE will handle it.
    # For reliability in this specific environment, we should try to ensure a wrapper exists.
    # Since we can't easily download one here without internet guarantees, we rely on the IDE opening or pre-installed tools.
fi

# Ensure executable if exists
if [ -f "$PROJECT_DIR/gradlew" ]; then
    chmod +x "$PROJECT_DIR/gradlew"
fi

# Gradle properties
echo "org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8" > "$PROJECT_DIR/gradle.properties"
echo "android.useAndroidX=true" >> "$PROJECT_DIR/gradle.properties"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
[ -f "$PROJECT_DIR/gradlew" ] && chmod +x "$PROJECT_DIR/gradlew"

# Open the project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "SimpleNotes" 120

# Record initial state
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="