#!/bin/bash
set -e
echo "=== Setting up implement_secure_file_sharing task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ------------------------------------------------------------------
# 1. Clean up previous artifacts
# ------------------------------------------------------------------
rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log 2>/dev/null || true

# ------------------------------------------------------------------
# 2. Prepare the LogShareApp project
#    (We base it on CalculatorApp to get a valid Gradle structure, 
#     then modify it to become LogShareApp)
# ------------------------------------------------------------------
BASE_SOURCE="/workspace/data/CalculatorApp"
PROJECT_DIR="/home/ga/AndroidStudioProjects/LogShareApp"

echo "Creating LogShareApp from base template..."
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p /home/ga/AndroidStudioProjects
cp -r "$BASE_SOURCE" "$PROJECT_DIR"

# Set ownership
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew"

# ------------------------------------------------------------------
# 3. Refactor project structure to "com.example.logshare"
# ------------------------------------------------------------------
OLD_PKG="com/example/calculator"
NEW_PKG="com/example/logshare"

# Move source files
mkdir -p "$PROJECT_DIR/app/src/main/java/$NEW_PKG"
rm -rf "$PROJECT_DIR/app/src/main/java/$OLD_PKG" 2>/dev/null || true

# Remove old specific files
rm -f "$PROJECT_DIR/app/src/main/java/$NEW_PKG/CalcEngine.kt" 2>/dev/null || true
rm -f "$PROJECT_DIR/app/src/main/java/$NEW_PKG/CalcActivity.kt" 2>/dev/null || true
rm -f "$PROJECT_DIR/app/src/main/java/$NEW_PKG/Calculator.kt" 2>/dev/null || true

# Create the specific MainActivity for this task
cat > "$PROJECT_DIR/app/src/main/java/$NEW_PKG/MainActivity.kt" << 'KT_EOF'
package com.example.logshare

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import java.io.File
import java.io.FileWriter
import java.io.IOException

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // We'll use a programmatic layout to avoid XML complexity for this task setup
        val layout = android.widget.LinearLayout(this)
        layout.orientation = android.widget.LinearLayout.VERTICAL
        layout.gravity = android.view.Gravity.CENTER
        
        val button = Button(this)
        button.text = "Share Log File"
        button.setOnClickListener { shareLogFile() }
        
        layout.addView(button)
        setContentView(layout)

        simulateLogCreation()
    }

    private fun simulateLogCreation() {
        try {
            val file = File(filesDir, "app_logs.txt")
            val writer = FileWriter(file)
            writer.append("Log entry 1: App started\n")
            writer.append("Log entry 2: User logged in\n")
            writer.append("Log entry 3: Critical error detected\n")
            writer.flush()
            writer.close()
        } catch (e: IOException) {
            e.printStackTrace()
        }
    }

    private fun shareLogFile() {
        val file = File(filesDir, "app_logs.txt")
        
        if (!file.exists()) {
            Toast.makeText(this, "Log file not found", Toast.LENGTH_SHORT).show()
            return
        }

        // TODO: Implement secure file sharing using FileProvider
        // CURRENTLY BROKEN: Using file:// URI causes FileUriExposedException on Android 7+
        val uri = Uri.fromFile(file)
        
        val intent = Intent(Intent.ACTION_SEND)
        intent.type = "text/plain"
        intent.putExtra(Intent.EXTRA_STREAM, uri)
        
        // This will crash or fail
        startActivity(Intent.createChooser(intent, "Share Logs"))
    }
}
KT_EOF

# Update AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'MANIFEST_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.logshare">

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="LogShareApp"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.AppCompat.Light">
        
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <!-- TODO: Add FileProvider here -->

    </application>

</manifest>
MANIFEST_EOF

# Update build.gradle.kts to reflect new namespace/applicationId
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'GRADLE_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.logshare"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.logshare"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    implementation("androidx.core:core-ktx:1.9.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.9.0")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}
GRADLE_EOF

# Fix settings.gradle.kts
echo 'rootProject.name = "LogShareApp"' > "$PROJECT_DIR/settings.gradle.kts"
echo 'include(":app")' >> "$PROJECT_DIR/settings.gradle.kts"

# Ensure permissions are correct after file creation
chown -R ga:ga "$PROJECT_DIR"

# ------------------------------------------------------------------
# 4. Open project in Android Studio
# ------------------------------------------------------------------
setup_android_studio_project "$PROJECT_DIR" "LogShareApp" 180

# ------------------------------------------------------------------
# 5. Capture Initial State
# ------------------------------------------------------------------
take_screenshot /tmp/task_start.png
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="