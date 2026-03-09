#!/bin/bash
set -e
echo "=== Setting up implement_runtime_permission task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project Paths
PROJECT_NAME="QuickSnap"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="app/src/main/java/com/example/quicksnap"
RES_DIR="app/src/main/res"

# 1. Clean up previous attempts
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 2. Create Project Structure
mkdir -p "$PROJECT_DIR/app/libs"
mkdir -p "$PROJECT_DIR/$PACKAGE_DIR"
mkdir -p "$PROJECT_DIR/$RES_DIR/layout"
mkdir -p "$PROJECT_DIR/$RES_DIR/values"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 3. Create Files

# settings.gradle.kts
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

# build.gradle.kts (Project)
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

# app/build.gradle.kts
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.quicksnap"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.quicksnap"
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
    implementation("androidx.activity:activity-ktx:1.8.2")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
EOF

# app/src/main/AndroidManifest.xml (MISSING PERMISSION)
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
        android:theme="@style/Theme.QuickSnap"
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

# Create dummy XML resources to prevent build errors
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo '<data-extraction-rules></data-extraction-rules>' > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
echo '<full-backup-content></full-backup-content>' > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26"
touch "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
touch "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml"

# app/src/main/res/values/strings.xml
cat > "$PROJECT_DIR/$RES_DIR/values/strings.xml" <<EOF
<resources>
    <string name="app_name">QuickSnap</string>
    <string name="open_camera">Open Camera</string>
</resources>
EOF

# app/src/main/res/values/themes.xml
cat > "$PROJECT_DIR/$RES_DIR/values/themes.xml" <<EOF
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.QuickSnap" parent="Theme.Material3.DayNight.NoActionBar">
    </style>
    <style name="Theme.QuickSnap" parent="Base.Theme.QuickSnap" />
</resources>
EOF

# app/src/main/res/layout/activity_main.xml
cat > "$PROJECT_DIR/$RES_DIR/layout/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <Button
        android:id="@+id/btnOpenCamera"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/open_camera"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# app/src/main/java/com/example/quicksnap/MainActivity.kt (MISSING LOGIC)
cat > "$PROJECT_DIR/$PACKAGE_DIR/MainActivity.kt" <<EOF
package com.example.quicksnap

import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val btnOpenCamera = findViewById<Button>(R.id.btnOpenCamera)
        btnOpenCamera.setOnClickListener {
            // BUG: Calls startCamera() directly without checking permissions!
            startCamera()
        }
    }

    private fun startCamera() {
        // In a real app, this would open the camera.
        // For this task, we simulate the action.
        Log.d("QuickSnap", "Camera Started")
        Toast.makeText(this, "Camera Started", Toast.LENGTH_SHORT).show()
    }
}
EOF

# Copy Gradle Wrapper from system if available, or generate it
if [ -d "/opt/android-studio/plugins/android/lib/templates/gradle/wrapper" ]; then
    cp -r /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/* "$PROJECT_DIR/gradle/wrapper/"
fi
# Ensure gradlew exists
if [ ! -f "$PROJECT_DIR/gradlew" ]; then
    # Simple fallback: assume gradle is in path or we can use local installation
    # But usually copying from another project is safer.
    # We'll copy from a known location in the env or rely on the agent to fix it?
    # No, setup must provide a working env.
    # Let's assume the env has a generic gradlew we can use or we create a basic one.
    # Ideally, we copy from /workspace/data if available.
    # Fallback: Create a minimal script that calls the system gradle
    echo '#!/bin/bash' > "$PROJECT_DIR/gradlew"
    echo 'gradle "$@"' >> "$PROJECT_DIR/gradlew"
    chmod +x "$PROJECT_DIR/gradlew"
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew"

# 4. Open Project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "QuickSnap" 180

# 5. Take Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="