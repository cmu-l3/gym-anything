#!/bin/bash
set -e

echo "=== Setting up remediate_accessibility_violations task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="AccessAll"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_PATH="com/example/accessall"

# 1. Clean previous run
rm -rf "$PROJECT_DIR"
rm -f /tmp/task_result.json

# 2. Create minimal Android Project structure
# We construct this manually to ensure a specific broken state without relying on external large downloads
mkdir -p "$PROJECT_DIR/app/src/main/java/$PACKAGE_PATH"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/res/drawable"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 3. Create build files
cat > "$PROJECT_DIR/settings.gradle.kts" <<EOF
rootProject.name = "$PROJECT_NAME"
include(":app")
EOF

cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.1.0" apply false
    id("org.jetbrains.kotlin.android") version "1.8.10" apply false
}
EOF

cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.accessall"
    compileSdk = 33

    defaultConfig {
        applicationId = "com.example.accessall"
        minSdk = 24
        targetSdk = 33
        versionCode = 1
        versionName = "1.0"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.9.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.9.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
EOF

# 4. Create Manifest
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <application
        android:allowBackup="true"
        android:label="@string/app_name"
        android:theme="@style/Theme.AccessAll">
        <activity
            android:name=".LoginActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 5. Create strings.xml (Missing the logo description)
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" <<EOF
<resources>
    <string name="app_name">AccessAll</string>
    <string name="login_button">Sign In</string>
    <string name="email_hint">Email</string>
    <string name="password_hint">Password</string>
    <string name="forgot_password">Forgot Password?</string>
</resources>
EOF

# 6. Create themes (Minimal)
mkdir -p "$PROJECT_DIR/app/src/main/res/values/themes"
cat > "$PROJECT_DIR/app/src/main/res/values/themes/themes.xml" <<EOF
<resources>
    <style name="Theme.AccessAll" parent="Theme.Material3.DayNight.NoActionBar">
        <item name="colorPrimary">@color/purple_500</item>
    </style>
</resources>
EOF
cat > "$PROJECT_DIR/app/src/main/res/values/colors.xml" <<EOF
<resources>
    <color name="purple_500">#FF6200EE</color>
    <color name="black">#FF000000</color>
    <color name="white">#FFFFFFFF</color>
</resources>
EOF

# 7. Create the BROKEN Layout File (activity_login.xml)
# Violations:
# - heights are 40dp (too small)
# - img_logo missing contentDescription
# - et_email missing autofillHints/inputType
# - tv_forgot_pass has low contrast color #AAAAAA
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_login.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout 
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:padding="16dp">

    <!-- VIOLATION 2: Missing contentDescription -->
    <ImageView
        android:id="@+id/img_logo"
        android:layout_width="100dp"
        android:layout_height="100dp"
        android:src="@android:drawable/sym_def_app_icon"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="32dp" />

    <!-- VIOLATION 3: Missing autofillHints, inputType incomplete -->
    <!-- VIOLATION 1: Height 40dp (too small) -->
    <EditText
        android:id="@+id/et_email"
        android:layout_width="0dp"
        android:layout_height="40dp"
        android:hint="@string/email_hint"
        app:layout_constraintTop_toBottomOf="@id/img_logo"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="32dp" />

    <!-- VIOLATION 1: Height 40dp (too small) -->
    <EditText
        android:id="@+id/et_password"
        android:layout_width="0dp"
        android:layout_height="40dp"
        android:hint="@string/password_hint"
        android:inputType="textPassword"
        app:layout_constraintTop_toBottomOf="@id/et_email"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="16dp" />

    <!-- VIOLATION 4: Low contrast color #AAAAAA -->
    <TextView
        android:id="@+id/tv_forgot_pass"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/forgot_password"
        android:textColor="#AAAAAA"
        app:layout_constraintTop_toBottomOf="@id/et_password"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="8dp" />

    <!-- VIOLATION 1: Height 40dp (too small) -->
    <Button
        android:id="@+id/btn_login"
        android:layout_width="0dp"
        android:layout_height="40dp"
        android:text="@string/login_button"
        app:layout_constraintTop_toBottomOf="@id/tv_forgot_pass"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="24dp" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# 8. Create Minimal Activity Class
cat > "$PROJECT_DIR/app/src/main/java/$PACKAGE_PATH/LoginActivity.kt" <<EOF
package com.example.accessall

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class LoginActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_login)
    }
}
EOF

# 9. Setup Gradle Wrapper (Copy from system or generate)
# Assuming SDK is installed, we can rely on Android Studio to fix wrapper or use installed gradle
# But for reliability, let's copy a generic wrapper if available or create properties
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" <<EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.0-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF
# Copy gradlew from a known location if possible, or create a dummy script that calls system gradle
# In this env, usually we can grab one from /opt or generate.
# We'll use the one from /workspace/data if available, otherwise assume `gradle` on path works
if [ -f "/opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew" ]; then
    cp "/opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew" "$PROJECT_DIR/"
else
    # Simple fallback
    echo '#!/bin/bash' > "$PROJECT_DIR/gradlew"
    echo 'gradle "$@"' >> "$PROJECT_DIR/gradlew"
fi
chmod +x "$PROJECT_DIR/gradlew"

# 10. Set ownership
chown -R ga:ga "$PROJECT_DIR"

# 11. Open Project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "$PROJECT_NAME" 180

# 12. Open the specific file to edit
su - ga -c "DISPLAY=:1 /opt/android-studio/bin/studio.sh $PROJECT_DIR/app/src/main/res/layout/activity_login.xml > /dev/null 2>&1 &"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="