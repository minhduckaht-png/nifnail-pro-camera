import AVFoundation
import Photos
import SwiftUI
import Combine

final class CameraViewModel: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var permissionMessage: String?
    @Published var exposureBias: Float = 0
    @Published var iso: Float = 100
    @Published var shutterSeconds: Double = 1.0 / 60.0
    @Published var isManualExposure = false
    @Published var hdrEnabled = false
    @Published var status = "Đang khởi tạo camera…"

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "nifnail.camera.session")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var isFrontCamera = false
    private var configured = false

    override init() {
        super.init()
        requestPermissionsAndConfigure()
    }

    private func requestPermissionsAndConfigure() {
        let group = DispatchGroup()
        var cameraOK = false
        var micOK = false

        group.enter()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            cameraOK = granted
            group.leave()
        }
        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            micOK = granted
            group.leave()
        }
        group.notify(queue: .main) {
            guard cameraOK else {
                self.permissionMessage = "Anh cần cấp quyền Camera trong Cài đặt iPhone."
                self.status = "Chưa có quyền camera"
                return
            }
            self.sessionQueue.async {
                self.configureSession(includeAudio: micOK)
            }
        }
    }

    private func configureSession(includeAudio: Bool) {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd4K3840x2160
        if !session.canSetSessionPreset(.hd4K3840x2160) {
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
        return discovery.devices.first
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
        let range = device.activeFormat
        iso = min(max(device.iso, range.minISO), range.maxISO)
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
        if let newISO { iso = newISO }
        if let newShutter { shutterSeconds = newShutter }
        guard isManualExposure else { return }
        setManualExposure(true)
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
                self.isFrontCamera.toggle()
                self.configureHDRIfSupported(device)
            } else {
                self.session.addInput(oldInput)
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.hdrEnabled = device.isVideoHDREnabled
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
