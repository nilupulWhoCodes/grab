"""Applies Grab's Android settings to the project that `flutter create` generates.

Run from the repo root after `flutter create --platforms=android .`
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
app = root / "android" / "app"

# --- AndroidManifest.xml -----------------------------------------------------
manifest = app / "src" / "main" / "AndroidManifest.xml"
text = manifest.read_text(encoding="utf-8")

permissions = """
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
"""

# Background playback + lock-screen controls (audio_service, used by
# just_audio_background).
audio_service = """
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
"""
if "READ_MEDIA_AUDIO" not in text:
    text = re.sub(r"(<manifest[^>]*>)", r"\1" + permissions, text, count=1)

text = re.sub(r'android:label="[^"]*"', 'android:label="Grab"', text, count=1)
if "requestLegacyExternalStorage" not in text:
    text = text.replace(
        "<application",
        '<application\n        android:requestLegacyExternalStorage="true"',
        1,
    )
if "com.ryanheise.audioservice.AudioService" not in text:
    i = text.rindex("</application>")
    text = text[:i] + audio_service.lstrip("\n") + "    " + text[i:]
manifest.write_text(text, encoding="utf-8")

# --- MainActivity must extend AudioServiceActivity ---------------------------
activities = list((app / "src" / "main").rglob("MainActivity.kt"))
if not activities:
    sys.exit("MainActivity.kt not found")
for act in activities:
    src = act.read_text(encoding="utf-8")
    package = re.search(r"^package\s+([\w.]+)", src, re.M).group(1)
    act.write_text(
        f"package {package}\n\n"
        "import com.ryanheise.audioservice.AudioServiceActivity\n\n"
        "class MainActivity : AudioServiceActivity()\n",
        encoding="utf-8",
    )

# --- build.gradle(.kts): minSdk 24 (needed by ffmpeg-kit) --------------------
gradle_kts = app / "build.gradle.kts"
gradle = app / "build.gradle"
if gradle_kts.exists():
    g = gradle_kts.read_text(encoding="utf-8")
    g = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 24", g, count=1)
    gradle_kts.write_text(g, encoding="utf-8")
elif gradle.exists():
    g = gradle.read_text(encoding="utf-8")
    g = re.sub(r"minSdk(Version)?\s+[^\n]+", "minSdkVersion 24", g, count=1)
    gradle.write_text(g, encoding="utf-8")
else:
    sys.exit("android/app/build.gradle(.kts) not found")

# --- R8 keep rules: ffmpeg-kit is called through JNI -------------------------
(app / "proguard-rules.pro").write_text(
    "-keep class com.arthenica.** { *; }\n"
    "-keep class com.antonkarpenko.** { *; }\n"
    "-dontwarn com.arthenica.**\n"
    "-dontwarn com.antonkarpenko.**\n",
    encoding="utf-8",
)

print("Android project patched.")
