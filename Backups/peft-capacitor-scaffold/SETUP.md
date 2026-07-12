# Peft Logbook — Android/iOS packaging + OTA updates

This mirrors exactly how the Finance Tracker app is set up: a Capacitor
shell around the single HTML file, self-hosted over-the-air updates via
`@capgo/capacitor-updater` pointed at a `latest.json` on GitHub (no paid
Capgo/Appflow account needed), and a hardware back button that's routed
through the app's own overlay stack instead of exiting.

Everything in this folder (`capacitor.config.json`, `package.json`,
`update.ps1`, `latest.json`, `www/index.html`, `bundles/`) is ready to drop
into a fresh project folder. `www/index.html` is v9.8 of Peft Logbook with
the native/OTA scaffolding already added.

## 1. One-time machine setup

You need Node.js (18+), and for native builds: Android Studio (Android) and
a Mac with Xcode (iOS — optional, skip if you're Android-only for now).

## 2. Create the GitHub repo

Create a **new, empty** repo: `storemybits-ui/ue-peft-logbook` (same owner
as `ue-finance-tracker`, public is simplest since `raw.githubusercontent.com`
serves public repo files with no auth).

```bash
git init
git remote add origin https://github.com/storemybits-ui/ue-peft-logbook.git
```

## 3. Install dependencies

From this folder:

```bash
npm install
```

This pulls in Capacitor core + CLI, the Android/iOS platform packages,
`@capgo/capacitor-updater` (the OTA engine), `@capacitor/app` (hardware back
button), `@capacitor/filesystem` (native Export/Restore), and
`@capacitor/local-notifications` + `@capacitor/haptics` + `@capacitor/splash-screen`
for parity with the Finance Tracker build.

## 4. Initialize Capacitor (first time only)

```bash
npx cap init "Peft Logbook" com.storemybits.peftlogbook --web-dir=www
```

This will offer to overwrite `capacitor.config.json` — say no, the one
already in this folder has the OTA + splash config pre-filled. (If it does
overwrite it, just re-paste the version from this folder.)

## 5. Add the native platforms

```bash
npx cap add android
npx cap add ios      # only if you have a Mac
npx cap sync
```

This generates the `android/` (and `ios/`) folders — full native Gradle/Xcode
projects that wrap `www/` in a WebView.

## 6. App icon & splash screen

Capacitor's asset generator will build every density from one source image:

```bash
npm install @capacitor/assets --save-dev
npx capacitor-assets generate --iconBackgroundColor "#0A1522" --splashBackgroundColor "#0A1522"
```

Drop a 1024x1024 `resources/icon.png` (and optionally `resources/splash.png`)
in this folder first — a simple logbook/wings mark on the `#0A1522` navy
works well against the app's own theme.

## 7. First build (Android)

```bash
npx cap open android
```

This opens Android Studio. Build -> Generate Signed Bundle/APK. For a
sideloadable APK to test on your own device, "APK" is simpler than "AAB"
(AAB is what you'd upload to Play Store). Keep the keystore somewhere safe —
you need the *same* keystore for every future signed build, OTA or not.

## 8. Push the first OTA release

`update.ps1` does the whole release step: reads the version out of
`www/index.html`, zips it into `bundles/peft-<version>.zip`, writes
`latest.json`, and pushes both to GitHub.

```powershell
.\update.ps1
```

(This folder already has `latest.json` and `bundles/peft-9.8.zip` for v9.8
pre-built, matching what's baked into the APK — so the very first launch
won't show an update prompt, which is correct. The *next* time you change
`www/index.html`, bump `APP_VERSION` and add a `CHANGELOG` entry for it,
then run `update.ps1` — that's the release you'll see prompted on-device.)

## Everyday workflow after this

For a **JS/HTML/CSS-only change** (the vast majority of updates):
1. Edit `www/index.html`, bump `const APP_VERSION = 'v9.9'` and add a
   `CHANGELOG["v9.9"]` entry describing what changed.
2. Run `update.ps1`.
3. Done — every installed app checks on launch and on resume, and offers a
   one-tap update with your changelog shown.

For a **native change** (new Capacitor plugin, permission, icon):
1. `npm install <plugin>` then `npx cap sync`.
2. Rebuild + re-sign the APK/IPA in Android Studio / Xcode and redistribute
   it directly (OTA cannot ship native code changes — that's the whole
   reason the store apps exist).

## What's already wired up in `www/index.html`

- **`APP_VERSION` / `CHANGELOG` / `MANIFEST_URL`** — near the top of the
  script, right after `STORE_KEY`.
- **`download()`** — now Capacitor-aware: writes straight to the device's
  Documents folder via `@capacitor/filesystem` when running natively, falls
  back to the normal browser download on the web build. Covers both the
  full JSON backup and every CSV export path, since all of them route
  through `download()`.
- **Hardware back button** — a dedicated script near the end of the file
  walks every overlay/modal in priority order (deepest first) and closes
  whichever is open, falling back to the Flights tab, then a confirm-to-exit
  dialog. Requires `@capacitor/app`.
- **OTA update manager (`OTA` object)** — `OTA.check()`, `OTA.apply()`,
  `OTA.bootChangelog()`, `OTA.history()`. A "Check for updates" / "What's
  new" pair of links sits under the version number at the bottom of
  Settings.
- **Capgo boot confirmation** — calls `notifyAppReady()` on launch so the
  updater doesn't roll back a good bundle.

No emojis anywhere in any of this — the update/close icons are inline SVG,
matching the rest of the app.
