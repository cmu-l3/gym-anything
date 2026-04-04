#!/bin/bash
set -e

echo "=== Setting up implement_biometric_auth task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project Paths
PROJECT_NAME="SecretDiary"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="$PROJECT_DIR/app/src/main/java/com/example/secretdiary"
RES_DIR="$PROJECT_DIR/app/src/main/res"

# Clean previous
rm -rf "$PROJECT_DIR"
mkdir -p "$PACKAGE_DIR"
mkdir -p "$RES_DIR/layout"
mkdir -p "$RES_DIR/values"

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

# 2. Project-level build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}
EOF

# 3. App-level build.gradle.kts (WITHOUT Biometric dependency)
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.secretdiary"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.secretdiary"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    
    buildFeatures {
        viewBinding = true
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
    testImplementation("junit:junit:4.13.2")
}
EOF

# 4. AndroidManifest.xml
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
        android:theme="@style/Theme.SecretDiary"
        tools:targetApi="31">
        <activity
            android:name=".LoginActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <activity android:name=".DiaryActivity" />
    </application>

</manifest>
EOF

# 5. LoginActivity.kt (INSECURE STARTING STATE)
cat > "$PACKAGE_DIR/LoginActivity.kt" <<EOF
package com.example.secretdiary

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

class LoginActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_login)

        val btnLogin = findViewById<Button>(R.id.btn_login)

        // TODO: Secure this! Currently it just logs in without checking anything.
        btnLogin.setOnClickListener {
            // Unsecured navigation
            val intent = Intent(this, DiaryActivity::class.java)
            startActivity(intent)
            finish()
        }
    }
}
EOF

# 6. DiaryActivity.kt (Dummy target)
cat > "$PACKAGE_DIR/DiaryActivity.kt" <<EOF
package com.example.secretdiary

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import android.widget.TextView

class DiaryActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_login) // Reusing layout for simplicity
        findViewById<TextView>(R.id.tv_title).text = "Secret Diary Entries"
    }
}
EOF

# 7. Layouts
cat > "$RES_DIR/layout/activity_login.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:padding="16dp">

    <TextView
        android:id="@+id/tv_title"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Secret Diary Login"
        android:textSize="24sp"
        android:layout_marginBottom="32dp"/>

    <Button
        android:id="@+id/btn_login"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Login" />

</LinearLayout>
EOF

# 8. Resources
cat > "$RES_DIR/values/strings.xml" <<EOF
<resources>
    <string name="app_name">SecretDiary</string>
</resources>
EOF

cat > "$RES_DIR/values/themes.xml" <<EOF
<resources>
    <style name="Theme.SecretDiary" parent="Theme.Material3.DayNight.NoActionBar">
        <item name="colorPrimary">@color/purple_500</item>
    </style>
</resources>
EOF

cat > "$RES_DIR/values/colors.xml" <<EOF
<resources>
    <color name="purple_500">#FF6200EE</color>
    <color name="black">#FF000000</color>
    <color name="white">#FFFFFFFF</color>
</resources>
EOF

# Also create backup rules to prevent build errors
mkdir -p "$RES_DIR/xml"
cat > "$RES_DIR/xml/backup_rules.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <include domain="sharedpref" path="."/>
    <include domain="database" path="."/>
</full-backup-content>
EOF
cat > "$RES_DIR/xml/data_extraction_rules.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <include domain="sharedpref" path="."/>
        <include domain="database" path="."/>
    </cloud-backup>
    <device-transfer>
        <include domain="sharedpref" path="."/>
        <include domain="database" path="."/>
    </device-transfer>
</data-extraction-rules>
EOF

# Set Permissions
chown -R ga:ga "$PROJECT_DIR"

# Initialize Gradle Wrapper (requires running gradle once, or copying. 
# Since we don't have internet guaranteed during setup to download wrapper, 
# we rely on the Android Studio installation's ability to generate it or use local one.
# For this task, we assume `gradlew` is needed. We will copy it from a known location if available, 
# or assume the user can run `gradle wrapper`. 
# To be safe, we'll try to generate it using the installed gradle if available, 
# otherwise we rely on Android Studio to fix it on open.)

echo "Project generated at $PROJECT_DIR"

# Open Android Studio
setup_android_studio_project "$PROJECT_DIR" "SecretDiary" 120

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="