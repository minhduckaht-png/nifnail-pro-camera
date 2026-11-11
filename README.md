# NIFNAIL PRO CAMERA

Native SwiftUI + AVFoundation camera starter for iPhone, with iPhone 11 Pro Max as the initial target.

## Current features
- Live rear/front camera preview.
- Dedicated still-photo capture and save to Photos.
- Video recording, selecting 4K when the active capture session supports it.
- Exposure compensation control.
- Optional manual ISO and shutter controls, bounded by the active camera format's reported limits.
- Video HDR requested only when the active camera format reports HDR support.
- Save completed photos and recordings to Photos.

## HDR and device expectations
The app does not implement multi-frame HDR merging. Still-photo processing is handled by the iPhone camera/AVFoundation pipeline; this source does not promise a particular Smart HDR result or a specific HDR file format. Video HDR is enabled only when AVFoundation reports support for the active camera format. Do not expect Dolby Vision recording on iPhone 11 Pro Max.

## Build and test
1. Open `NIFNAIL_PRO_CAMERA.xcodeproj` on a Mac with Xcode.
2. Select the `NIFNAIL_PRO_CAMERA` target.
3. In Signing & Capabilities, select an Apple Developer team (or configure signing for a personal test device).
4. Connect the iPhone, select it as the run destination, then press Run.
5. Approve camera, microphone and Photos permissions.

GitHub stores the source code; it does not compile or install the iOS app by itself. This branch has not yet been built or tested on a physical iPhone. Verify compilation in Xcode before relying on camera or HDR behavior.
