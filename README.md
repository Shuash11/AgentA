# AgentA App Icon Specification

This document provides the design requirements and implementation steps for the **AgentA** application icon.

## 1. Icon Design Concept
The icon should represent speed, intelligence, and the powerful AI capabilities of the assistant.

- **Central Element:** A stylized, sharp lightning bolt (Bolt/Lightning motif).
- **Background:** Deep Midnight Blue or Rich Dark Navy.
- **Color Palette:**
  - Lightning Bolt: `#FFB300` (Amber/Golden) with a slight glow.
  - Background: `#0F172A` (Midnight Blue).
- **Aesthetic:** Minimalist, Futuristic, Premium. Circular or Squircle shape.

### Reference SVG Design
The following SVG code represents the base design for the icon:

```xml
<svg width="512" height="512" viewBox="0 0 512 512" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="256" cy="256" r="256" fill="#0F172A"/>
  <path d="M288 32L112 288H240L224 480L400 224H272L288 32Z" fill="#FFB300" stroke="#FFD54F" stroke-width="8" stroke-linejoin="round"/>
  <defs>
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="15" result="blur" />
      <feComposite in="SourceGraphic" in2="blur" operator="over" />
    </filter>
  </defs>
</svg>
```

---

## 2. Instructions for the Future Agent

### Step A: Generate High-Res Image
Use an AI image generation tool or convert the SVG above into a high-quality **1024x1024 PNG** file.
- **Target Path:** `assets/images/logo.png` (Create the folder if it doesn't exist).

### Step B: Install Launcher Icons Dependency
Add `flutter_launcher_icons` to your `dev_dependencies` in `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.13.1
```

### Step C: Configure Icon Generation
Add the following configuration code at the bottom of your `pubspec.yaml`:

```yaml
flutter_launcher_icons:
  android: "launcher_icon"
  ios: true
  image_path: "assets/images/logo.png"
  min_sdk_android: 21
```

### Step D: Run Generation Command
Execute the following command in the terminal to generate all icon sizes for Android and iOS:

```bash
flutter pub run flutter_launcher_icons:main
```

---

## 3. Branding Notes
- **App Name:** AgentA
- **Core Theme:** Lightning Intelligence
- **Accent Color:** Amber (#FFB300)

---

## 4. Google Sign-In Setup (Android)

Native Google sign-in shows an instant "cancelled" sheet when the SHA-1 /
OAuth / Supabase config mismatches. Full runbook (package
`com.agenta.AgentA`, keytool commands, Cloud Console + Supabase steps, adb
logcat diagnosis, signing debt note): [docs/google-signin-setup.md](docs/google-signin-setup.md).
