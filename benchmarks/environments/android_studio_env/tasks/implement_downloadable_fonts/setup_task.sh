#!/bin/bash
echo "=== Setting up implement_downloadable_fonts task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -rf /tmp/task_result.json 2>/dev/null || true
rm -rf /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true

# Project Configuration
PROJECT_DIR="/home/ga/AndroidStudioProjects/QuoteApp"
PACKAGE="com.example.quoteapp"

# 1. Create a fresh project structure (simulating a basic "Empty Views Activity")
# We use a base project if available, or generate a minimal one.
# For robustness, we'll assume we can copy a base template or generate it.
# Here we will generate a minimal valid project structure to ensure self-containment.

echo "Generating base project at $PROJECT_DIR..."
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/quoteapp"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/res/font" # Empty initially
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# Copy Gradle Wrapper (assuming standard env location, else create dummy)
if [ -d "/opt/android-studio/plugins/android/lib/templates/gradle/wrapper" ]; then
    cp -r /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/* "$PROJECT_DIR/gradle/wrapper/" 2>/dev/null || true
fi
# Ensure gradlew exists
cat > "$PROJECT_DIR/gradlew" << 'EOF'
#!/bin/sh
exec gradle "$@"
EOF
chmod +x "$PROJECT_DIR/gradlew"

# settings.gradle.kts
cat > "$PROJECT_DIR/settings.gradle.kts" << EOF
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
rootProject.name = "QuoteApp"
include(":app")
EOF

# project build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" << EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

# app build.gradle.kts
cat > "$PROJECT_DIR/app/build.gradle.kts" << EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.quoteapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.quoteapp"
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

# AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="QuoteApp"
        android:supportsRtl="true"
        android:theme="@style/Theme.QuoteApp"
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

# MainActivity.kt
cat > "$PROJECT_DIR/app/src/main/java/com/example/quoteapp/MainActivity.kt" << EOF
package com.example.quoteapp

import androidx.appcompat.app.AppCompatActivity
import android.os.Bundle

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# activity_main.xml (Starting State)
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <TextView
        android:id="@+id/quote_text"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="The only way to do great work is to love what you do."
        android:padding="16dp"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# themes.xml
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << EOF
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.QuoteApp" parent="Theme.Material3.DayNight.NoActionBar">
        <!-- Customize your light theme here. -->
    </style>
    <style name="Theme.QuoteApp" parent="Base.Theme.QuoteApp" />
</resources>
EOF

# Create dummy XML rules to satisfy manifest
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo "<data-extraction-rules></data-extraction-rules>" > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
echo "<full-backup-content></full-backup-content>" > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
chmod +x "$PROJECT_DIR/gradlew"

# Open project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "QuoteApp" 180

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="