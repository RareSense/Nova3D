# Nova3D — Client App

The Flutter/Dart web client for Nova3D. For what Nova3D is and how the code-native pipeline works, see the [project README](../README.md).

This client connects to the hosted Nova3D service (currently closed-source). No local backend is required.

## Prerequisites

The client is built with Flutter/Dart. If you don't have Flutter 3.24+ installed, set it up first:

<details>
<summary>💻 macOS</summary>

Install Flutter via [Homebrew](https://brew.sh):

```bash
brew install --cask flutter
flutter doctor
```

</details>

<details>
<summary>🪟 Windows</summary>

Install Flutter via [Chocolatey](https://chocolatey.org) (run PowerShell as Administrator):

```powershell
choco install flutter
```

Then close and reopen your terminal, and verify:

```powershell
flutter doctor
```

> Don't have Chocolatey? [Install it here](https://chocolatey.org/install), or follow the [manual Flutter install guide](https://docs.flutter.dev/install/manual).

</details>

<details>
<summary>🐧 Linux</summary>

Install Flutter via Snap:

```bash
sudo snap install flutter --classic
flutter sdk-path   # confirm install path
flutter doctor
```

</details>

Once `flutter doctor` shows no blocking issues, continue with Quick Start below.

## Quick Start

Get it running locally in under 2 minutes. Requires [Flutter 3.24+](https://flutter.dev).

```bash
# 1. Clone and install
git clone https://github.com/RareSense/Nova3D.git
cd Nova3D/app
flutter pub get

# 2. Run local UI
# Note: Port 5555 is required for OAuth redirect authorization
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 5555
```

1. Open `http://127.0.0.1:5555`
2. Sign in (Google/Email).
3. **Settings** → Add your API Key (OpenRouter, OpenAI, Anthropic, or Gemini).
4. Enter a prompt and generate.

## Features

- **Integrated viewport:** built-in Three.js editor with transform tools, snapping, and material editing.
- **Local caching:** models are cached in-browser; view your history even after remote URLs expire.
- **Reference images:** attach a photo to guide the spatial logic of the generated script.
- **Production build:** `flutter build web --release` for static hosting.

## Troubleshooting

- **Auth loops:** always use `http://127.0.0.1:5555`. Using `localhost:5555` will cause Google Sign-In to fail due to strict OAuth origin policies.

- **API key not working / generations failing silently:** make sure your key is entered under **Settings → API Key** and that you've selected the matching provider (OpenRouter, OpenAI, Anthropic, or Gemini). A key for the wrong provider will fail immediately. **Avoid Gemini free-tier keys** — Nova3D's pipeline is token-intensive and free-tier Gemini quota is low enough that it may not function at all. Use a paid-tier Gemini key, or switch to OpenRouter, OpenAI, or Anthropic.

- **Nothing happens after clicking Generate (no error shown):** usually the client can't reach the backend. If you're on the default setup, make sure you haven't overridden `API_BASE_URL` to a local address. The default build points to `nova3d.xyz` — no local backend is needed.

- **Self-hosting a backend:** by default this client talks to the `nova3d.xyz` hosted API (closed-source). To point at your own backend, pass `--dart-define=API_BASE_URL=https://your-api.com` at build or run time. **Do not set this to a `localhost` address unless you have a fully configured local backend running** — doing so will return 400 errors on every generation. If unsure, leave the flag out and use the hosted service.
