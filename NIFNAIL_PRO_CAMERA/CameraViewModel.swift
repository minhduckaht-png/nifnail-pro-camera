import AVFoundation
import Photos
import SwiftUI
import Combine

final class CameraViewModel: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isCapturingPhoto = false
    @Published var permissionMessage: String?
    @Published var exposureBias: Float = 0
    @Published var iso: Float = 100
    @Published var shutterSeconds: Double = 1.0 / 60.0
    @Published var isManualExposure = false
    @Published var hdrEnabled = false
    @Published var status = "Đang khởi tạo camera…"
    @Published var isoRange: ClosedRange<Double> = 32...800
    @Published var shutterRange: ClosedRange<Double> = (1.0 / 240.0)...(1.0 / 15.0)

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "nifnail.camera.session")
    private let photoQueue = DispatchQueue(label: "nifnail.camera.photo")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var isFrontCamera = false
    private var configured = false

    override init() {
        super.init()
        requestPermissionsAndConfigure()
    }

    private func requestPermissionsAndConfigure() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    self.permissionMessage = "Anh cần cấp quyền Camera trong Cài đặt iPhone."
                    self.status = "Chưa có quyền camera"
                }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] micGranted in
                guard let self else { return }
                self.sessionQueue.async {
                    self.configureSession(includeAudio: micGranted)
                }
            }
        }
    }

    private func configureSession(includeAudio: Bool) {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canSetSessionPreset(.hd4K3840x2160) {
            session.sessionPreset = .hd4K3840x2160
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        guard let camera = cameraDevice(position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.status = "Không thể mở camera" }
            return
        }
        session.addInput(input)
        currentInput = input

        if includeAudio,
           let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        configureHDRIfSupported(camera)
        session.commitConfiguration()
        configured = true
        session.startRunning()
        DispatchQueue.main.async {
            self.status = "Sẵn sàng"
            self.hdrEnabled = camera.isVideoHDREnabled
            self.updateExposureLimits(for: camera)
        }
    }

    private func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera],
            mediaType: .video,
            position: position
        )
        if position == .back {
            return discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
                ?? discovery.devices.first
        }
        return discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
            ?? discovery.devices.first
    }

    private func configureHDRIfSupported(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.activeFormat.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = true
                device.isVideoHDREnabled = true
            } else {
                device.isVideoHDREnabled = false
            }
            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async { self.status = "Không chỉnh được HDR: \(error.localizedDescription)" }
        }
    }

    private func updateExposureLimits(for device: AVCaptureDevice) {
        let format = device.activeFormat
        let minISO = Double(format.minISO)
        let maxISO = Double(format.maxISO)
        let minShutter = CMTimeGetSeconds(format.minExposureDuration)
        let maxShutter = CMTimeGetSeconds(format.maxExposureDuration)
        guard minISO.isFinite, maxISO.isFinite, minShutter.isFinite, maxShutter.isFinite,
              minISO < maxISO, minShutter > 0, minShutter < maxShutter else { return }

        isoRange = minISO...maxISO
        // UI uses shorter-to-longer exposure values; clamp the current selection to this format.
        let lower = max(minShutter, 1.0 / 8000.0)
        let upper = min(maxShutter, 1.0)
        if lower < upper { shutterRange = lower...upper }
        iso = min(max(iso, format.minISO), format.maxISO)
        shutterSeconds = min(max(shutterSeconds, lower), upper)
    }

    func setBias(_ value: Float) {
        exposureBias = value
        sessionQueue.async {
            guard let device = self.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = min(max(value, device.minExposureTargetBias), device.maxExposureTargetBias)
                device.setExposureTargetBias(clamped)
                device.unlockForConfiguration()
            } catch { }
        }
    }

    func setManualExposure(_ enabled: Bool) {
        isManualExposure = enabled
        sessionQueue.async {
            guard let device = self.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if enabled {
                    let duration = CMTime(seconds: self.shutterSeconds, preferredTimescale: 1_000_000_000)
                    let safeDuration = CMTimeMinimum(CMTimeMaximum(duration, device.activeFormat.minExposureDuration), device.activeFormat.maxExposureDuration)
                    let safeISO = min(max(self.iso, device.activeFormat.minISO), device.activeFormat.maxISO)
                    device.setExposureModeCustom(duration: safeDuration, iso: safeISO, completionHandler: nil)
                } else if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }

    func updateManualExposure(iso newISO: Float? = nil, shutter newShutter: Double? = nil) {
        if let newISO { iso = min(max(newISO, Float(isoRange.lowerBound)), Float(isoRange.upperBound)) }
        if let newShutter { shutterSeconds = min(max(newShutter, shutterRange.lowerBound), shutterRange.upperBound) }
        guard isManualExposure else { return }
        sessionQueue.async {
            guard let device = self.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let duration = CMTime(seconds: self.shutterSeconds, preferredTimescale: 1_000_000_000)
                let safeDuration = CMTimeMinimum(CMTimeMaximum(duration, device.activeFormat.minExposureDuration), device.activeFormat.maxExposureDuration)
                let safeISO = min(max(self.iso, device.activeFormat.minISO), device.activeFormat.maxISO)
                device.setExposureModeCustom(duration: safeDuration, iso: safeISO, completionHandler: nil)
                device.unlockForConfiguration()
            } catch { }
        }
    }

    func capturePhoto() {
        sessionQueue.async {
            guard self.configured, !self.isCapturingPhoto, !self.movieOutput.isRecording else { return }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            if let device = self.currentInput?.device,
               device.position == .back,
               device.hasFlash,
               self.photoOutput.supportedFlashModes.contains(NSNumber(value: AVCaptureDevice.FlashMode.off.rawValue)) {
                settings.flashMode = .off
            }
            DispatchQueue.main.async {
                self.isCapturingPhoto = true
                self.status = "Đang chụp ảnh…"
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func switchCamera() {
        guard !isRecording else { return }
        sessionQueue.async {
            guard let oldInput = self.currentInput else { return }
            let newPosition: AVCaptureDevice.Position = self.isFrontCamera ? .back : .front
            guard let device = self.cameraDevice(position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(oldInput)
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput
                self.isFrontCamera = (newPosition == .front)
                self.configureHDRIfSupported(device)
            } else {
                self.session.addInput(oldInput)
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.hdrEnabled = device.isVideoHDREnabled
                self.updateExposureLimits(for: device)
                self.status = "Đã đổi camera"
            }
        }
    }

    func toggleRecording() {
        sessionQueue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            } else {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("NIFNAIL_\(UUID().uuidString).mov")
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }
}

extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.isCapturingPhoto = false
                self.status = "Chụp ảnh thất bại: \(error?.localizedDescription ?? "Không tạo được tệp ảnh")"
            }
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.isCapturingPhoto = false
                    self.status = "Chưa được cấp quyền lưu Ảnh"
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }) { success, saveError in
                DispatchQueue.main.async {
                    self.isCapturingPhoto = false
                    self.status = success ? "Đã lưu ảnh vào Ảnh" : "Không lưu được ảnh: \(saveError?.localizedDescription ?? "Lỗi không rõ")"
                }
            }
        }
    }
}

extension CameraViewModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.isRecording = true
            self.status = "Đang quay…"
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            if let error {
                self.status = "Lỗi ghi video: \(error.localizedDescription)"
                return
            }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async { self.status = "Chưa được cấp quyền lưu Ảnh" }
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
                }) { success, saveError in
                    DispatchQueue.main.async {
                        self.status = success ? "Đã lưu video vào Ảnh" : "Không lưu được: \(saveError?.localizedDescription ?? "Lỗi không rõ")"
                    }
                    try? FileManager.default.removeItem(at: outputFileURL)
                }
            }
        }
    }
}
