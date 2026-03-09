#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up add_foreground_service task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/AndroidStudioProjects/SyncApp"

# Clean up any previous attempts
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# --- Create project structure ---
echo "Creating SyncApp project structure..."

mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/syncapp"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/test/java/com/example/syncapp"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# --- Root build.gradle.kts ---
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.21" apply false
}
EOF

# --- settings.gradle.kts ---
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
rootProject.name = "SyncApp"
include(":app")
EOF

# --- gradle.properties ---
cat > "$PROJECT_DIR/gradle.properties" << 'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
EOF

# --- local.properties ---
cat > "$PROJECT_DIR/local.properties" << 'EOF'
sdk.dir=/opt/android-sdk
EOF

# --- app/build.gradle.kts ---
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.syncapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.syncapp"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}
EOF

# --- proguard-rules.pro ---
cat > "$PROJECT_DIR/app/proguard-rules.pro" << 'EOF'
# Add project specific ProGuard rules here.
EOF

# --- AndroidManifest.xml (initial state - NO service, NO foreground permissions) ---
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.SyncApp">
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

# --- MainActivity.kt ---
cat > "$PROJECT_DIR/app/src/main/java/com/example/syncapp/MainActivity.kt" << 'EOF'
package com.example.syncapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# --- activity_main.xml ---
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <TextView
        android:id="@+id/textView"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/app_name"
        android:textSize="24sp"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# --- strings.xml ---
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">SyncApp</string>
</resources>
EOF

# --- themes.xml ---
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'EOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.SyncApp" parent="Theme.MaterialComponents.DayNight.DarkActionBar">
        <item name="colorPrimary">@color/purple_500</item>
        <item name="colorPrimaryVariant">@color/purple_700</item>
        <item name="colorOnPrimary">@color/white</item>
    </style>
</resources>
EOF

# --- colors.xml ---
cat > "$PROJECT_DIR/app/src/main/res/values/colors.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
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

# --- Mipmap placeholder (use Android default) ---
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-hdpi"
# Create a minimal valid PNG for the launcher icon (1x1 pixel)
python3 -c "
import struct, zlib
def create_png(path):
    # Minimal 1x1 red PNG
    sig = b'\\x89PNG\\r\\n\\x1a\\n'
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)
    raw = zlib.compress(b'\\x00\\xff\\x00\\x00')
    with open(path, 'wb') as f:
        f.write(sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', raw) + chunk(b'IEND', b''))
create_png('$PROJECT_DIR/app/src/main/res/mipmap-hdpi/ic_launcher.png')
create_png('$PROJECT_DIR/app/src/main/res/mipmap-hdpi/ic_launcher_round.png')
"

# --- Download Gradle wrapper ---
echo "Setting up Gradle wrapper..."
GRADLE_VERSION="8.4"

# Download Gradle to generate wrapper
if [ ! -f "/opt/gradle-${GRADLE_VERSION}/bin/gradle" ]; then
    echo "Downloading Gradle ${GRADLE_VERSION}..."
    wget -q "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -O /tmp/gradle-bin.zip
    unzip -q /tmp/gradle-bin.zip -d /opt/
    rm -f /tmp/gradle-bin.zip
fi

# Generate wrapper
cd "$PROJECT_DIR"
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 /opt/gradle-${GRADLE_VERSION}/bin/gradle wrapper --gradle-version ${GRADLE_VERSION} 2>/dev/null || {
    # Fallback: create wrapper files manually
    echo "Creating Gradle wrapper manually..."
    
    cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << GWEOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
GWEOF
    
    # Copy wrapper jar from installed Gradle
    cp "/opt/gradle-${GRADLE_VERSION}/lib/gradle-wrapper.jar" "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null || true
    
    # Create gradlew script
    cat > "$PROJECT_DIR/gradlew" << 'GRADLEW'
#!/bin/sh
exec java -classpath "$APP_HOME/gradle/wrapper/gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain "$@"
GRADLEW
    chmod +x "$PROJECT_DIR/gradlew"
}

chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null || true

# --- Save initial manifest state for verification ---
cp "$PROJECT_DIR/app/src/main/AndroidManifest.xml" /tmp/initial_manifest.xml

# --- Record initial file list ---
find "$PROJECT_DIR/app/src/main/java" -name "*.kt" | sort > /tmp/initial_kotlin_files.txt

# --- Set ownership ---
chown -R ga:ga "$PROJECT_DIR"

# --- Pre-download Gradle distribution for faster builds ---
echo "Pre-downloading Gradle distribution..."
su - ga -c "cd $PROJECT_DIR && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 ANDROID_SDK_ROOT=/opt/android-sdk ./gradlew --version" 2>/dev/null || true

# --- Open project in Android Studio ---
echo "Opening SyncApp in Android Studio..."
setup_android_studio_project "$PROJECT_DIR" "SyncApp" 120

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Project: $PROJECT_DIR"
echo "Initial manifest saved to /tmp/initial_manifest.xml"