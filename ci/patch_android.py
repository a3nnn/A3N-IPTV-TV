"""Turns the default Flutter Android project into an Android TV app.

Run after:  flutter create --platforms=android --org com.a3n --project-name a3n_iptv_tv .
"""
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"
MANIFEST = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"

# 1) Icons + TV home-screen banner
for src in (ROOT / "android_res").rglob("*.png"):
    dst = RES / src.relative_to(ROOT / "android_res")
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    print("copied", dst.relative_to(ROOT))

# 2) Manifest
m = MANIFEST.read_text(encoding="utf-8")


def add_after_manifest_open(text, snippet):
    if snippet.split()[0] in text and snippet in text:
        return text
    return re.sub(r"(<manifest\b[^>]*>)", r"\1\n    " + snippet, text, count=1)


for line in [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-feature android:name="android.software.leanback" android:required="false"/>',
    '<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>',
]:
    if line not in m:
        m = add_after_manifest_open(m, line)

# <application ...> attributes
m = re.sub(r'android:label="[^"]*"', 'android:label="A3N IPTV Player"', m, count=1)


def set_app_attr(text, name, value):
    if f"{name}=" in text:
        return re.sub(rf'{name}="[^"]*"', f'{name}="{value}"', text, count=1)
    return re.sub(r"<application\b", f'<application\n        {name}="{value}"', text, count=1)


m = set_app_attr(m, "android:banner", "@drawable/banner")
m = set_app_attr(m, "android:usesCleartextTraffic", "true")  # IPTV hosts are plain http

# Show the app in the Android TV launcher
if "LEANBACK_LAUNCHER" not in m:
    m = m.replace(
        '<category android:name="android.intent.category.LAUNCHER"/>',
        '<category android:name="android.intent.category.LAUNCHER"/>\n'
        '                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
        1,
    )

MANIFEST.write_text(m, encoding="utf-8")
print(m)

for check in ["INTERNET", "LEANBACK_LAUNCHER", "android:banner", "usesCleartextTraffic"]:
    assert check in m, f"manifest patch failed: {check}"
print("Android TV patch OK")
