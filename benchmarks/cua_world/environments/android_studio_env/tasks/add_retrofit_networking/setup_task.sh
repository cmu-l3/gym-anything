#!/bin/bash
set -e
echo "=== Setting up add_retrofit_networking task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -rf /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -rf /home/ga/AndroidStudioProjects/PostViewer 2>/dev/null || true

# Define Project Paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/PostViewer"
APP_DIR="$PROJECT_DIR/app"
PKG_DIR="$APP_DIR/src/main/java/com/example/postviewer"

# Create Directory Structure
mkdir -p "$PKG_DIR"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

echo "Generating project files..."

# 1. settings.gradle.kts
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
rootProject.name = "PostViewer"
include(":app")
EOF

# 2. Root build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.1.1" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
    id("com.google.devtools.ksp") version "1.9.0-1.0.13" apply false
}
EOF

# 3. app/build.gradle.kts (Minimal start state)
cat > "$APP_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.devtools.ksp")
}

android {
    namespace = "com.example.postviewer"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.postviewer"
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
    implementation("androidx.core:core-ktx:1.10.1")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.9.0")
    // Agent must add networking dependencies here
}
EOF

# 4. AndroidManifest.xml
mkdir -p "$APP_DIR/src/main"
cat > "$APP_DIR/src/main/AndroidManifest.xml" << 'EOF'
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
        android:theme="@style/Theme.PostViewer"
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

# 5. MainActivity.kt
cat > "$PKG_DIR/MainActivity.kt" << 'EOF'
package com.example.postviewer

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# 6. Resources (minimal)
mkdir -p "$APP_DIR/src/main/res/values"
mkdir -p "$APP_DIR/src/main/res/layout"
mkdir -p "$APP_DIR/src/main/res/xml"

cat > "$APP_DIR/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">PostViewer</string>
</resources>
EOF

cat > "$APP_DIR/src/main/res/values/themes.xml" << 'EOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.PostViewer" parent="Theme.Material3.DayNight.NoActionBar">
    </style>
    <style name="Theme.PostViewer" parent="Base.Theme.PostViewer" />
</resources>
EOF

cat > "$APP_DIR/src/main/res/layout/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
</androidx.constraintlayout.widget.ConstraintLayout>
EOF

cat > "$APP_DIR/src/main/res/xml/data_extraction_rules.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup><include domain="root" /></cloud-backup>
    <device-transfer><include domain="root" /></device-transfer>
</data-extraction-rules>
EOF

cat > "$APP_DIR/src/main/res/xml/backup_rules.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <include domain="sharedpref" path="."/>
    <include domain="database" path="."/>
</full-backup-content>
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;

# Try to populate Gradle Wrapper if available on system, otherwise agent must trigger it
if [ -d "/opt/android-studio/plugins/android/lib/templates/gradle/wrapper" ]; then
    cp -r /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/* "$PROJECT_DIR/" 2>/dev/null || true
fi
# Fallback: check other projects
SAMPLE_WRAPPER=$(find /home/ga -name "gradle-wrapper.jar" | head -1)
if [ -n "$SAMPLE_WRAPPER" ]; then
    cp "$(dirname "$SAMPLE_WRAPPER")/gradle-wrapper.jar" "$PROJECT_DIR/gradle/wrapper/"
    cp "$(dirname "$SAMPLE_WRAPPER")/gradle-wrapper.properties" "$PROJECT_DIR/gradle/wrapper/"
    cp "$(dirname "$SAMPLE_WRAPPER")/../../gradlew" "$PROJECT_DIR/"
    cp "$(dirname "$SAMPLE_WRAPPER")/../../gradlew.bat" "$PROJECT_DIR/"
    chmod +x "$PROJECT_DIR/gradlew"
fi

# Open project
setup_android_studio_project "$PROJECT_DIR" "PostViewer" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="