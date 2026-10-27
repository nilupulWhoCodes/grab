# Grab

An Android app with two parts:

1. **Music**: a music player for the MP3s already on the phone. It scans internal storage and SD cards (skipping ringtones and notification sounds), with search, Recent/A–Z sorting and shuffle all. A full Now Playing screen has seeking, shuffle and repeat. Playback keeps going with the screen off, with controls on the lock screen and in the notification shade.
2. **MP3**: browse YouTube's mobile site inside the app. When a video is open, a **MP3** button appears. Pick a quality (128/192/320 kbps) and the audio is downloaded and converted to MP3 on the phone, then saved to `Music/Grab`. A Downloads tab lists saved tracks. New downloads show up in Music right away.

Everything runs on the phone. No server is needed.

## Install

GitHub Actions builds the APK on every push to `main` (see the **Actions** tab, artifact `grab-apk`):

- `grab-arm64.apk`: almost every phone from the last ~8 years
- `grab-armv7.apk`: older 32-bit phones

Copy the APK to the phone, open it and allow "Install unknown apps" when Android asks.

## How it works

| Piece | Package |
| --- | --- |
| In-app browser | `webview_flutter` |
| Finding the audio stream | `youtube_explode_dart` |
| Converting to MP3 | `ffmpeg_kit_flutter_new_audio` (LAME) |
| Playback | `just_audio` + `just_audio_background` |

The `android/` folder isn't committed. CI generates it with `flutter create` and then applies `tool/patch_android.py` (permissions, background-playback service, minSdk 24, R8 keep rules).

## If downloads stop working

YouTube changes its site regularly. Most breakage gets fixed by updating `youtube_explode_dart` and rebuilding.

For personal use only, with your own uploads or content you have permission to download. This app can't be published on the Play Store.
