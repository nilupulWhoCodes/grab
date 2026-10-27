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
manifest.write_text(text, encoding="utf-8")

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
