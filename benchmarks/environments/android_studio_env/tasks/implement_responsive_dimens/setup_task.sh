#!/bin/bash
set -e
echo "=== Setting up implement_responsive_dimens task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project Paths
PROJECT_NAME="SocialApp"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
APP_DIR="$PROJECT_DIR/app"

# 1. Clean up previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true

# 2. Create Project Structure manually (mimicking a "messy" prototype)
mkdir -p "$APP_DIR/src/main/java/com/example/socialapp"
mkdir -p "$APP_DIR/src/main/res/layout"
mkdir -p "$APP_DIR/src/main/res/values"
mkdir -p "$APP_DIR/src/main/res/drawable"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 3. Create settings.gradle.kts
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
rootProject.name = "SocialApp"
include(":app")
EOF

# 4. Create project-level build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

# 5. Create app-level build.gradle.kts
cat > "$APP_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.socialapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.socialapp"
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

# 6. Create AndroidManifest.xml
cat > "$APP_DIR/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="SocialApp"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.SocialApp"
        tools:targetApi="31">
        <activity
            android:name=".ProfileActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
EOF

# 7. Create ProfileActivity.kt
cat > "$APP_DIR/src/main/java/com/example/socialapp/ProfileActivity.kt" << 'EOF'
package com.example.socialapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class ProfileActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_profile)
    }
}
EOF

# 8. Create the "MESSY" layout file with hardcoded values
cat > "$APP_DIR/src/main/res/layout/activity_profile.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout 
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:padding="16dp">

    <ImageView
        android:id="@+id/avatar"
        android:layout_width="80dp"
        android:layout_height="80dp"
        android:src="@drawable/ic_launcher_background"
        android:layout_marginTop="24dp"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent" />

    <TextView
        android:id="@+id/name"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Jane Doe"
        android:textSize="24sp"
        android:textStyle="bold"
        android:layout_marginTop="16dp"
        app:layout_constraintTop_toBottomOf="@id/avatar"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent" />

    <TextView
        android:id="@+id/bio"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:text="Android Developer | Coffee Enthusiast"
        android:textSize="14sp"
        android:gravity="center"
        android:layout_marginTop="8dp"
        android:layout_marginHorizontal="24dp"
        app:layout_constraintTop_toBottomOf="@id/name"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent" />

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:layout_marginTop="32dp"
        app:layout_constraintTop_toBottomOf="@id/bio">
        
        <TextView
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="Followers"
            android:textSize="14sp"
            android:gravity="center"/>
            
        <TextView
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="Following"
            android:textSize="14sp"
            android:gravity="center"/>
    </LinearLayout>

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# 9. Create basic dimens.xml (Empty/Minimal)
cat > "$APP_DIR/src/main/res/values/dimens.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Add your dimensions here -->
</resources>
EOF

# 10. Create dummy resources to prevent build errors
mkdir -p "$APP_DIR/src/main/res/mipmap-anydpi-v26"
touch "$APP_DIR/src/main/res/xml/data_extraction_rules.xml"
cat > "$APP_DIR/src/main/res/xml/backup_rules.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
</full-backup-content>
EOF
cat > "$APP_DIR/src/main/res/values/themes.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.SocialApp" parent="Theme.MaterialComponents.DayNight.DarkActionBar" />
</resources>
EOF
# Create dummy drawable
cat > "$APP_DIR/src/main/res/drawable/ic_launcher_background.xml" << 'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:height="108dp" android:width="108dp" android:viewportHeight="108" android:viewportWidth="108">
    <path android:fillColor="#3DDC84" android:pathData="M0,0h108v108h-108z"/>
</vector>
EOF

# 11. Setup Gradle Wrapper (Try to copy from existing projects or system if available)
# If we can't find a jar, we can't build easily without 'gradle' in path.
# Assuming standard Android Studio env has a way to bootstrap or gradle installed.
# We will check if `gradle` is in path, if so init wrapper.
if command -v gradle &> /dev/null; then
    cd "$PROJECT_DIR"
    gradle wrapper
else
    # Fallback: Create dummy wrapper script that fails gracefully if invoked
    # but allows project open. Agent should ideally fix or IDE fixes it.
    # BEST EFFORT: The task is about editing XML, IDE build might fail if wrapper missing.
    # We will assume the agent can handle Gradle sync or the IDE creates it.
    echo "Warning: gradle command not found, skipping wrapper generation."
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null || true

# 12. Open Project
setup_android_studio_project "$PROJECT_DIR" "SocialApp" 180

# 13. Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="