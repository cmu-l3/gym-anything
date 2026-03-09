#!/bin/bash
set -e

echo "=== Setting up add_notification_channels task ==="
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ---- Create the NotepadApp project structure ----
PROJECT_DIR="/home/ga/AndroidStudioProjects/NotepadApp"

# Clean up any previous attempt
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Create standard Android project directory structure
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/notepadapp"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/res/drawable"
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-hdpi"
mkdir -p "$PROJECT_DIR/app/src/test/java/com/example/notepadapp"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# ---- Root build.gradle.kts ----
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# ---- settings.gradle.kts ----
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
rootProject.name = "NotepadApp"
include(":app")
EOF

# ---- gradle.properties ----
cat > "$PROJECT_DIR/gradle.properties" << 'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
EOF

# ---- Gradle wrapper properties ----
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# Attempt to copy local gradle wrapper if available to save download time
if [ -f /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew ]; then
    cp /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew "$PROJECT_DIR/gradlew"
    chmod +x "$PROJECT_DIR/gradlew"
else
    # Fallback minimal script
    cat > "$PROJECT_DIR/gradlew" << 'GRADLEW'
#!/bin/sh
APP_NAME="Gradle"
APP_BASE_NAME=$(basename "$0")
CLASSPATH=$APP_HOME/gradle/wrapper/gradle-wrapper.jar
JAVACMD=${JAVA_HOME:+$JAVA_HOME/bin/}java
exec "$JAVACMD" "-Xmx64m" "-classpath" "$CLASSPATH" org.gradle.wrapper.GradleWrapperMain "$@"
GRADLEW
    chmod +x "$PROJECT_DIR/gradlew"
fi

# Try to find the wrapper jar
find /opt/android-studio -name "gradle-wrapper.jar" -exec cp {} "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" \; -quit 2>/dev/null || true
if [ ! -f "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" ]; then
    # Create dummy jar to trigger download or fail gracefully (agent usually has net access)
    echo "Warning: gradle-wrapper.jar not pre-seeded"
fi

# ---- App module build.gradle.kts ----
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.notepadapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.notepadapp"
        minSdk = 26
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
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
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

# ---- ProGuard rules ----
touch "$PROJECT_DIR/app/proguard-rules.pro"

# ---- AndroidManifest.xml (Initial State) ----
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher"
        android:supportsRtl="true"
        android:theme="@style/Theme.NotepadApp">
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

# ---- MainActivity.kt ----
cat > "$PROJECT_DIR/app/src/main/java/com/example/notepadapp/MainActivity.kt" << 'EOF'
package com.example.notepadapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# ---- activity_main.xml ----
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="NotepadApp"
        android:textSize="24sp"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# ---- Resources ----
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">NotepadApp</string>
</resources>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'EOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.NotepadApp" parent="Theme.MaterialComponents.DayNight.DarkActionBar">
        <item name="colorPrimary">@color/purple_500</item>
        <item name="colorPrimaryVariant">@color/purple_700</item>
        <item name="colorOnPrimary">@color/white</item>
    </style>
</resources>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values/colors.xml" << 'EOF'
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

# Create a placeholder icon
touch "$PROJECT_DIR/app/src/main/res/mipmap-hdpi/ic_launcher.png"

# ---- Set Ownership ----
chown -R ga:ga "$PROJECT_DIR"

# ---- Record Initial State ----
find "$PROJECT_DIR/app/src/main/java" -name "*.kt" | wc -l > /tmp/initial_kt_count.txt

# ---- Open Project in Android Studio ----
echo "Opening NotepadApp in Android Studio..."
setup_android_studio_project "$PROJECT_DIR" "NotepadApp" 120

# ---- Initial Screenshot ----
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="