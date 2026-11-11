# NIFNAIL PRO CAMERA

Native SwiftUI + AVFoundation starter project for iPhone.

## What is included
- Live rear/front camera preview
- Video recording, with 4K selected when the device supports it
- Exposure compensation control
- Optional manual ISO and shutter controls when supported by the active camera
- HDR recording enabled only when the active camera format reports support
- Save completed recordings to Photos

## Important device limitation
This project does not create a multi-exposure HDR merge for moving video. That technique can cause ghosting and flicker. The app asks AVFoundation to enable camera HDR only when the selected hardware format supports it. iPhone 11 Pro Max does not support Dolby Vision video recording; do not expect Dolby Vision output.

## Build
1. Open `NIFNAIL_PRO_CAMERA.xcodeproj` on a Mac with Xcode.
2. Select the `NIFNAIL_PRO_CAMERA` target.
3. In Signing & Capabilities, choose your Apple ID Team.
4. Connect the iPhone, select it as the run destination, then press Run.
5. Approve camera, microphone and Photos permissions.

GitHub stores this source code; it does not compile or install the iOS app by itself.
