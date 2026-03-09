#!/bin/bash
set -e
echo "=== Setting up add_static_app_shortcuts task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous artifacts
rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log 2>/dev/null || true

# 2. Define Project Paths
PROJECT_NAME="QuickNotes"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="com/example/quicknotes"

# Remove existing project to ensure clean state
rm -rf "$PROJECT_DIR" 2>/dev/null || true

# 3. Create Project Structure
mkdir -p "$PROJECT_DIR/app/src/main/java/$PACKAGE_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/res/drawable"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
# Note: we do NOT create res/xml yet, user must do that (or at least populate it)
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 4. Generate Build Files

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
    namespace = "com.example.quicknotes"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.quicknotes"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
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
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
}
EOF

# 5. Generate Source Code

# AndroidManifest.xml
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
        android:theme="@style/Theme.QuickNotes"
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
cat > "$PROJECT_DIR/app/src/main/java/$PACKAGE_DIR/MainActivity.kt" <<EOF
package com.example.quicknotes

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import android.widget.TextView

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val messageView = findViewById<TextView>(R.id.message)
        
        // Handle shortcut intents for demonstration
        when (intent.action) {
            "com.example.quicknotes.CREATE_NOTE" -> messageView.text = "Creating New Note..."
            "com.example.quicknotes.SEARCH" -> messageView.text = "Searching..."
            else -> messageView.text = "Welcome to QuickNotes"
        }
    }
}
EOF

# 6. Generate Resources

# Layout
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:gravity="center"
    android:orientation="vertical">

    <TextView
        android:id="@+id/message"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Welcome to QuickNotes"
        android:textSize="24sp" />

</LinearLayout>
EOF

# Strings
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" <<EOF
<resources>
    <string name="app_name">QuickNotes</string>
</resources>
EOF

# Themes
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" <<EOF
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.QuickNotes" parent="Theme.Material3.DayNight.NoActionBar">
    </style>
    <style name="Theme.QuickNotes" parent="Base.Theme.QuickNotes" />
</resources>
EOF

# Backup Rules (Required for build)
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
cat > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <include domain="sharedpref" path="."/>
    <exclude domain="sharedpref" path="device.xml"/>
</full-backup-content>
EOF
cat > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <include domain="sharedpref" path="."/>
        <exclude domain="sharedpref" path="device.xml"/>
    </cloud-backup>
    <device-transfer>
        <include domain="sharedpref" path="."/>
        <exclude domain="sharedpref" path="device.xml"/>
    </device-transfer>
</data-extraction-rules>
EOF

# Icons (ic_add.xml, ic_search.xml)
cat > "$PROJECT_DIR/app/src/main/res/drawable/ic_add.xml" <<EOF
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24"
    android:tint="?attr/colorControlNormal">
  <path
      android:fillColor="@android:color/white"
      android:pathData="M19,13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>
</vector>
EOF

cat > "$PROJECT_DIR/app/src/main/res/drawable/ic_search.xml" <<EOF
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24"
    android:tint="?attr/colorControlNormal">
  <path
      android:fillColor="@android:color/white"
      android:pathData="M15.5,14h-0.79l-0.28,-0.27C15.41,12.59 16,11.11 16,9.5 16,5.91 13.09,3 9.5,3S3,5.91 3,9.5 5.91,16 9.5,16c1.61,0 3.09,-0.59 4.23,-1.57l0.27,0.28v0.79l5,4.99L20.49,19l-4.99,-5zM9.5,14C7.01,14 5,11.99 5,9.5S7.01,5 9.5,5 14,7.01 14,9.5 11.99,14 9.5,14z"/>
</vector>
EOF

# 7. Finalize Permissions and Open Studio
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;

# Record task start time
date +%s > /tmp/task_start_time.txt

# Open Project
setup_android_studio_project "$PROJECT_DIR" "QuickNotes" 120

# Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="