#!/bin/bash
set -e

echo "=== Setting up add_dark_theme_support task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous runs
rm -rf /tmp/task_result.json 2>/dev/null || true
rm -rf /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -rf /home/ga/AndroidStudioProjects/WeatherApp 2>/dev/null || true

# Define project structure
PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"
PACKAGE_DIR="$PROJECT_DIR/app/src/main/java/com/example/weatherapp"
RES_DIR="$PROJECT_DIR/app/src/main/res"

mkdir -p "$PACKAGE_DIR"
mkdir -p "$RES_DIR/values"
mkdir -p "$RES_DIR/layout"
mkdir -p "$RES_DIR/mipmap-hdpi" # minimal placeholder for launcher icon

# 1. Create settings.gradle.kts
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
rootProject.name = "WeatherApp"
include(":app")
EOF

# 2. Create build.gradle.kts (Project)
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}
EOF

# 3. Create app/build.gradle.kts
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.weatherapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.weatherapp"
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

# 4. Create AndroidManifest.xml
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
        android:theme="@style/Theme.WeatherApp"
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

# Create dummy backup rules to prevent build errors if referenced
mkdir -p "$RES_DIR/xml"
echo '<data-extraction-rules></data-extraction-rules>' > "$RES_DIR/xml/data_extraction_rules.xml"
echo '<full-backup-content></full-backup-content>' > "$RES_DIR/xml/backup_rules.xml"

# 5. Create strings.xml
cat > "$RES_DIR/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">WeatherApp</string>
    <string name="welcome_message">Weather Forecast</string>
    <string name="toggle_theme">Toggle Theme</string>
</resources>
EOF

# 6. Create colors.xml (Light colors only)
cat > "$RES_DIR/values/colors.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="black">#FF000000</color>
    <color name="white">#FFFFFFFF</color>
    <color name="colorPrimary">#6750A4</color>
    <color name="colorOnPrimary">#FFFFFF</color>
    <color name="colorPrimaryContainer">#EADDFF</color>
    <color name="colorOnPrimaryContainer">#21005D</color>
    <color name="colorSecondary">#625B71</color>
    <color name="colorOnSecondary">#FFFFFF</color>
    <color name="colorSurface">#FEF7FF</color>
    <color name="colorOnSurface">#1D1B20</color>
    <color name="colorBackground">#FEF7FF</color>
    <color name="colorOnBackground">#1D1B20</color>
</resources>
EOF

# 7. Create themes.xml (Light parent)
cat > "$RES_DIR/values/themes.xml" << 'EOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <!-- Base application theme. -->
    <style name="Base.Theme.WeatherApp" parent="Theme.Material3.Light.NoActionBar">
        <!-- Customize your light theme here. -->
        <item name="colorPrimary">@color/colorPrimary</item>
        <item name="colorOnPrimary">@color/colorOnPrimary</item>
        <item name="colorPrimaryContainer">@color/colorPrimaryContainer</item>
        <item name="colorOnPrimaryContainer">@color/colorOnPrimaryContainer</item>
        <item name="colorSecondary">@color/colorSecondary</item>
        <item name="colorOnSecondary">@color/colorOnSecondary</item>
        <item name="colorSurface">@color/colorSurface</item>
        <item name="colorOnSurface">@color/colorOnSurface</item>
        <item name="android:colorBackground">@color/colorBackground</item>
        <item name="colorOnBackground">@color/colorOnBackground</item>
    </style>

    <style name="Theme.WeatherApp" parent="Base.Theme.WeatherApp" />
</resources>
EOF

# 8. Create layout/activity_main.xml
cat > "$RES_DIR/layout/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="?attr/colorSurface"
    tools:context=".MainActivity">

    <TextView
        android:id="@+id/titleText"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/welcome_message"
        android:textColor="?attr/colorOnSurface"
        android:textSize="24sp"
        app:layout_bottom_toTopOf="@id/themeButton"
        app:layout_constraintLeft_toLeftOf="parent"
        app:layout_constraintRight_toRightOf="parent"
        app:layout_top_toTopOf="parent"
        app:layout_constraintVertical_chainStyle="packed" />

    <Button
        android:id="@+id/themeButton"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/toggle_theme"
        android:layout_marginTop="32dp"
        app:layout_bottom_toBottomOf="parent"
        app:layout_constraintLeft_toLeftOf="parent"
        app:layout_constraintRight_toRightOf="parent"
        app:layout_top_toBottomOf="@id/titleText" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# 9. Create MainActivity.kt
cat > "$PACKAGE_DIR/MainActivity.kt" << 'EOF'
package com.example.weatherapp

import android.os.Bundle
import android.widget.Button
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val btn = findViewById<Button>(R.id.themeButton)
        btn.setOnClickListener {
            // TODO: Implement theme toggle here
        }
    }
}
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;

# Try to download/install gradle wrapper if possible, otherwise rely on IDE
if [ -d "/opt/android-studio/plugins/android/lib/templates/gradle/wrapper" ]; then
    echo "Copying Gradle wrapper from Android Studio templates..."
    mkdir -p "$PROJECT_DIR/gradle/wrapper"
    cp -r /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/* "$PROJECT_DIR/" 2>/dev/null || true
    chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null || true
fi

# Open project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "WeatherApp" 180

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="