#!/bin/bash
set -e
echo "=== Setting up implement_pip_mode task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="StreamFlix"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="app/src/main/java/com/example/streamflix"
RES_LAYOUT_DIR="app/src/main/res/layout"
RES_VALUES_DIR="app/src/main/res/values"

# Clean up previous run
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/$PACKAGE_DIR"
mkdir -p "$PROJECT_DIR/$RES_LAYOUT_DIR"
mkdir -p "$PROJECT_DIR/$RES_VALUES_DIR"

echo "Generating project files..."

# 1. settings.gradle.kts
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

# 2. build.gradle.kts (Project)
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# 3. app/build.gradle.kts
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.streamflix"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.streamflix"
        minSdk = 26
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

# 4. AndroidManifest.xml (Initial state: No PiP)
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
        android:theme="@style/Theme.StreamFlix">
        
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <!-- Task Target: PlayerActivity -->
        <!-- Missing supportsPictureInPicture and configChanges -->
        <activity
            android:name=".PlayerActivity"
            android:exported="false" />
            
    </application>
</manifest>
EOF

# 5. Resources (strings, themes, xml rules)
cat > "$PROJECT_DIR/$RES_VALUES_DIR/strings.xml" <<EOF
<resources>
    <string name="app_name">StreamFlix</string>
    <string name="close">Close</string>
    <string name="play">Play</string>
</resources>
EOF

cat > "$PROJECT_DIR/$RES_VALUES_DIR/themes.xml" <<EOF
<resources>
    <style name="Theme.StreamFlix" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="colorPrimary">@color/purple_500</item>
    </style>
    <color name="purple_500">#FF6200EE</color>
</resources>
EOF

mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo "<data-extraction-rules></data-extraction-rules>" > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
echo "<full-backup-content></full-backup-content>" > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap"
touch "$PROJECT_DIR/app/src/main/res/mipmap/ic_launcher.png" # Dummy

# 6. Layouts
# activity_main.xml
cat > "$PROJECT_DIR/$RES_LAYOUT_DIR/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    
    <Button
        android:id="@+id/btnWatch"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Watch Video"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />
</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# activity_player.xml
cat > "$PROJECT_DIR/$RES_LAYOUT_DIR/activity_player.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@android:color/black">

    <VideoView
        android:id="@+id/videoView"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

    <Button
        android:id="@+id/closeButton"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/close"
        android:layout_margin="16dp"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintEnd_toEndOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# 7. Kotlin Source Code

# MainActivity.kt
cat > "$PROJECT_DIR/$PACKAGE_DIR/MainActivity.kt" <<EOF
package com.example.streamflix

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        findViewById<Button>(R.id.btnWatch).setOnClickListener {
            startActivity(Intent(this, PlayerActivity::class.java))
        }
    }
}
EOF

# PlayerActivity.kt (Initial State)
cat > "$PROJECT_DIR/$PACKAGE_DIR/PlayerActivity.kt" <<EOF
package com.example.streamflix

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Bundle
import android.util.Rational
import android.view.View
import android.widget.Button
import android.widget.VideoView
import androidx.appcompat.app.AppCompatActivity

class PlayerActivity : AppCompatActivity() {

    private lateinit var closeButton: Button
    private lateinit var videoView: VideoView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_player)

        closeButton = findViewById(R.id.closeButton)
        videoView = findViewById(R.id.videoView)

        closeButton.setOnClickListener {
            finish()
        }

        // Simulate playing a video
        // videoView.setVideoPath(...) 
        // videoView.start()
    }

    // TODO: Implement Picture-in-Picture mode
    // 1. Override onUserLeaveHint to enter PiP
    // 2. Override onPictureInPictureModeChanged to hide the close button
}
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew"

# Initial build to ensure cache is hot (speeds up agent work)
echo "Pre-building project..."
cd "$PROJECT_DIR"
su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; ./gradlew assembleDebug" || echo "Warning: Initial build failed, but continuing..."

# Calculate initial file hashes
md5sum "$PROJECT_DIR/app/src/main/AndroidManifest.xml" > /tmp/manifest_initial_hash
md5sum "$PROJECT_DIR/app/src/main/java/com/example/streamflix/PlayerActivity.kt" > /tmp/activity_initial_hash

# Open in Android Studio
setup_android_studio_project "$PROJECT_DIR" "StreamFlix" 120

# Capture initial state
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="