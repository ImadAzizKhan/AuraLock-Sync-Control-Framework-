# 🔒 AuraLock (SyncControl Framework)
**A Real-Time, Hardware-Integrated Telemetry & Command Framework built for Couples using Flutter, Node.js, and Firebase.**

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-43853D?style=for-the-badge&logo=node.js&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-039BE5?style=for-the-badge&logo=Firebase&logoColor=white)
![Socket.io](https://img.shields.io/badge/Socket.io-black?style=for-the-badge&logo=socket.io&badgeColor=010101)

## 📌 Overview
AuraLock is a highly specialized, dual-node architecture consisting of an **Admin (Commander)** app and a **Client (Sub-Station)** app, designed specifically for couples to maintain a deep, real-time digital connection. 

It is engineered for instant state synchronization, intimate communication, remote hardware overriding, and emergency telemetry tracking. This framework demonstrates deep Android OS integrations natively through Flutter, utilizing background services, audio focus hijacking, custom URL schemes, and persistent screen overlays.

## ✨ Core Features
* 💖 **The 'Miss You' Heartbeat:** A core bonding feature allowing partners to instantly trigger affectionate alerts and priority notifications on each other's devices when they are missing one another.
* 🚨 **Emergency Telemetry Radar:** Activates **only** during an SOS/Danger event to save battery. Once triggered, it streams continuous live GPS coordinates and speed via WebSockets directly to the Commander's radar, complete with dynamic Google Maps routing.
* 🛡️ **Forced Screen Takeover:** Deploys a persistent, un-killable system overlay on the Client node using `flutter_overlay_window` for critical interventions.
* 🔊 **Hardware Volume Overrides:** Triggers high-amplitude emergency alarms that force-bypass Android's "Do Not Disturb" and silent profiles using native `AudioFocus` streams.
* 📥 **3-Tier Verification Engine:** An Inbox-style verification system for tasks (Direct, Media Proof, or Manual Admin Approval). Includes an automated penalty executioner for expired deadlines.
* 📿 **Physical Locket (NFC) Integration:** Executes real-time Socket.io payloads (like the 'Miss You' heartbeat or SOS) simply by tapping a physical NFC locket against the phone, utilizing custom deep-links (`amore://`).

---

## 📂 Repository Structure
* `/Admin (Commander)` - The control interface app (Flutter).
* `/Client_user` - The telemetry and execution app (Flutter).
* `/Server` - The Node.js WebSocket relay.

---

## 🚀 Installation & Setup Guide

### Step 1: Database Setup (Firebase)
For security, API keys are excluded from this repository. You must link your own Firebase project:
1. Install Firebase CLI: `npm install -g firebase-tools`
2. Open terminal in both the `Admin (Commander)` and `Client_user` directories.
3. Run: `flutterfire configure`
4. Select your Firebase project. This will automatically generate the required `firebase_options.dart` files for both apps.

### Step 2: Backend Setup (Local / Render)
1. Navigate to the server folder:
   ```bash
   cd Server
   npm install
2. **Local Testing:**
   * Download your Firebase Admin SDK Private Key from the Firebase Console.
   * Rename it to `firebase-key.json` and place it in the `/Server` root directory.
   * Run the server: `node server.js`
3. **Cloud Hosting (Render.com):**
   * Link this repository to a Render Web Service.
   * Go to the Environment section in Render. Add a "Secret File" named `firebase-key.json` and paste your Firebase Admin JSON contents inside.

### Step 3: Running the Apps
Navigate to the app directories and run:
```bash
flutter clean
flutter pub get
flutter run

## 📿 Step 4: NFC Locket Setup & Usage
AuraLock bridges physical jewelry with digital actions using NFC. Tapping a programmed NFC tag to the device will instantly launch the app (even from the background) and execute the assigned WebSocket command.

**How to program your NFC tags:**
1. Purchase standard NDEF-compatible NFC tags/stickers (e.g., NTAG215) and place them inside a locket or on a keychain.
2. Download an NFC writing application from the Play Store (e.g., *NFC Tools*).
3. Select "Write" -> "Add a Record" -> "URL / URI".
4. Program the tag using AuraLock's custom deep-link schemes:
   * To trigger the Heart/'Miss You' signal: Write `amore://missyou`
   * To trigger the SOS/Danger Alarm: Write `amore://danger`
5. Write the record to the tag. Your physical hardware is now linked to the AuraLock ecosystem!

---

## ⚠️ Disclaimer & Privacy
This framework requires extensive system permissions (Draw over other apps, Background Location, Activity Recognition, Microphone). It was developed as a private proof-of-concept for consensual testing of remote-control mechanics between couples and is not intended for public commercial distribution.