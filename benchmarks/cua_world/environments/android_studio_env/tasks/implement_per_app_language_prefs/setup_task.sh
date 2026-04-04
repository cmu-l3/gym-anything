#!/bin/bash
set -e

echo "=== Setting up implement_per_app_language_prefs task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous artifacts
rm -rf /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -rf /home/ga/AndroidStudioProjects/PolyglotReader 2>/dev/null || true

# 2. Create Project Directory Structure
PROJECT_DIR="/home/ga/AndroidStudioProjects/PolyglotReader"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/polyglot"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/res/values-fr"
mkdir -p "$PROJECT_DIR/app/src/main/res/values-es"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 3. Write Project Files

# settings.gradle.kts
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
rootProject.name = "PolyglotReader"
include(":app")
EOF

# build.gradle.kts (Project level - minimal)
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

# app/build.gradle.kts
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.polyglot"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.polyglot"
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
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
EOF

# AndroidManifest.xml
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
        android:theme="@style/Theme.PolyglotReader"
        tools:targetApi="31">
        
        <!-- TODO: Register localeConfig here -->

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

# Create dummy rules files to satisfy manifest references
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo '<data-extraction-rules></data-extraction-rules>' > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
echo '<full-backup-content></full-backup-content>' > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"

# MainActivity.kt
cat > "$PROJECT_DIR/app/src/main/java/com/example/polyglot/MainActivity.kt" << 'EOF'
package com.example.polyglot

import android.os.Bundle
import android.widget.Button
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        findViewById<Button>(R.id.btn_en).setOnClickListener {
            // TODO: Switch to English
        }

        findViewById<Button>(R.id.btn_fr).setOnClickListener {
            // TODO: Switch to French
        }

        findViewById<Button>(R.id.btn_es).setOnClickListener {
            // TODO: Switch to Spanish
        }
    }
}
EOF

# Layout: activity_main.xml
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:padding="16dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/greeting"
        android:textSize="24sp"
        android:layout_marginBottom="32dp"/>

    <Button
        android:id="@+id/btn_en"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="English" />

    <Button
        android:id="@+id/btn_fr"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Français" />

    <Button
        android:id="@+id/btn_es"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Español" />

</LinearLayout>
EOF

# Strings
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">PolyglotReader</string>
    <string name="greeting">Hello World!</string>
</resources>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values-fr/strings.xml" << 'EOF'
<resources>
    <string name="app_name">Lecteur Polyglotte</string>
    <string name="greeting">Bonjour le monde!</string>
</resources>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values-es/strings.xml" << 'EOF'
<resources>
    <string name="app_name">Lector Políglota</string>
    <string name="greeting">¡Hola Mundo!</string>
</resources>
EOF

# Theme
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'EOF'
<resources>
    <style name="Theme.PolyglotReader" parent="Theme.MaterialComponents.DayNight.DarkActionBar">
        <item name="colorPrimary">@color/purple_500</item>
        <item name="colorPrimaryVariant">@color/purple_700</item>
        <item name="colorOnPrimary">@color/white</item>
    </style>
    <color name="purple_500">#FF6200EE</color>
    <color name="purple_700">#FF3700B3</color>
    <color name="white">#FFFFFFFF</color>
</resources>
EOF

# Copy Gradle Wrapper from system if available, else we rely on IDE to generate/fix
if [ -d "/opt/android-studio/plugins/android/lib/templates/gradle/wrapper" ]; then
   cp -r /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/* "$PROJECT_DIR/gradle/wrapper/"
fi
# Ensure gradlew exists (borrowing from any installed template or just creating a dummy that delegates to system gradle)
# Since we don't have a reliable source for the binary jar in this text script, 
# we will rely on Android Studio's import process to fix the wrapper, 
# OR use the 'gradle' command from path if the wrapper fails.
# However, for 'setup_android_studio_project' to work best, we should provide a wrapper.
# Let's try to copy from a potentially existing project in /workspace/data if available.
if [ -d "/workspace/data/SunflowerApp" ]; then
    cp -r /workspace/data/SunflowerApp/gradle "$PROJECT_DIR/"
    cp /workspace/data/SunflowerApp/gradlew "$PROJECT_DIR/"
    cp /workspace/data/SunflowerApp/gradlew.bat "$PROJECT_DIR/"
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null || true

# 4. Open Project
setup_android_studio_project "$PROJECT_DIR" "PolyglotReader" 180

# 5. Initial Screenshot
take_screenshot /tmp/task_start.png

# 6. Record timestamp
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="