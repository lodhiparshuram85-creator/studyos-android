# StudyOS — Android-only build

This package contains the StudyOS Flutter source plus a GitHub Actions workflow that can compile an Android APK in the cloud. It does **not** include a precompiled APK yet.

## Build it using only your phone (GitHub account required)
1. Sign in to GitHub in your phone browser and create a **new repository** named `studyos-android`.
2. Upload the contents of this folder to the repository's root (make sure `.github/workflows/build-android.yml` is included). GitHub's website may require using its desktop-site option for folder uploads.
3. Open the repository's **Actions** tab. If asked, enable Actions.
4. Select **Build StudyOS Android APK**, tap **Run workflow**, then run it on the `main` branch.
5. Wait for the workflow to finish successfully. Open the completed run and download the artifact named **StudyOS-Android-APK**.
6. Extract the downloaded ZIP on your phone to get `app-release.apk`. Tap the APK and allow installation from that source if Android asks.

## Notes
- GitHub builds the APK; no PC or local Flutter installation is needed for this route.
- The APK is not signed for Play Store distribution. It is suitable for direct testing/installing on your own device.
- This is source code and an automated build workflow, not a tested binary. The first build may reveal compatibility issues that need fixing.
- Only Android is targeted; Windows build scripts have been removed.
