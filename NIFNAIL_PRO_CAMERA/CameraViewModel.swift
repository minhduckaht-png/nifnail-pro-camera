import AVFoundation
import Photos
import SwiftUI
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins

final class CameraViewModel: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isCapturingPhoto = false
    @Published var permissionMessage: String?
    @Published var exposureBias: Float = 0
    @Published var iso: Float = 100
    @Published var shutterSeconds: Double = 1.0 / 60.0
    @Published var isManualExposure = false
    @Published var hdrEnabled = false
    @Published var isManualWhiteBalance = false
    @Published var whiteBalanceTemperature: Double = 5500
    @Published var whiteBalanceTint: Double = 0
    @Published var selectedLook = "Natural"
    @Published var status = "Đang khởi tạo camera…"
    @Published var isoRange: ClosedRange<Double> = 32...800
    @Published var shutterRange: ClosedRange<Double> = (1.0 / 240.0)...(1.0 / 15.0)

    let session = AVCaptureSession()
    let lookNames = [
        "Natural", "Clean", "Bright", "Soft", "Vivid", "Warm", "Cool", "Pastel",
        "Film 400", "Kodak Gold", "Portra", "Ektar", "Fuji 400H", "Classic Chrome",
        "Vintage", " faded film", "Cine Teal", "Cine Orange", "Cine Bleach",
        "Noir", "Mono", "Sepia", "Black Mist", "Dream Glow", "Matte", "Drama"
    ]

    private let sessionQueue = DispatchQueue(label: "nifnail.camera.session")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let ciContext = CIContext()
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
                self.sessionQueue.async { self.configureSession(includeAudio: micGranted) }
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

        if includeAudio, let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic), session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            photoOutput.isHighResolutionCaptureEnabled = true
        }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        session.commitConfiguration()
        configured = true
        session.startRunning()
        DispatchQueue.main.async {
            self.status = "Sẵn sàng"
            self.hdrEnabled = false
            self.updateExposureLimits(for: camera)
        }
    }

    private func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera],
            mediaType: .video, position: position)
        if position == .back {
            return discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? discovery.devices.first
        }
        return discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? discovery.devices.first
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
                device.setExposureTargetBias(min(max(value, device.minExposureTargetBias), device.maxExposureTargetBias), completionHandler: nil)
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

    func setManualWhiteBalance(_ enabled: Bool) {
        isManualWhiteBalance = enabled
        sessionQueue.async {
            guard let device = self.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if enabled {
                    let values = AVCaptureWhiteBalanceTemperatureAndTintValues(temperature: Float(self.whiteBalanceTemperature), tint: Float(self.whiteBalanceTint))
                    var gains = device.deviceWhiteBalanceGains(for: values)
                    let maxGain = device.maxWhiteBalanceGain
                    gains.redGain = min(max(gains.redGain, 1), maxGain)
                    gains.greenGain = min(max(gains.greenGain, 1), maxGain)
                    gains.blueGain = min(max(gains.blueGain, 1), maxGain)
                    device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }

    func updateWhiteBalance(temperature: Double? = nil, tint: Double? = nil) {
        if let temperature { whiteBalanceTemperature = min(max(temperature, 2500), 10000) }
        if let tint { whiteBalanceTint = min(max(tint, -150), 150) }
        guard isManualWhiteBalance else { return }
        setManualWhiteBalance(true)
    }

    private func applySelectedLook(to input: CIImage) -> CIImage {
        let name = selectedLook
        var image = input
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        var saturation: Float = 1
        var contrast: Float = 1
        var brightness: Float = 0
        switch name {
        case "Clean": saturation = 1.05; contrast = 1.04; brightness = 0.025
        case "Bright": saturation = 1.0; contrast = 0.96; brightness = 0.09
        case "Soft": saturation = 0.92; contrast = 0.88; brightness = 0.035
        case "Vivid": saturation = 1.35; contrast = 1.12
        case "Warm", "Kodak Gold": saturation = 1.12; contrast = 1.04
        case "Cool": saturation = 0.96; contrast = 1.05
        case "Pastel", "Fuji 400H": saturation = 0.78; contrast = 0.91; brightness = 0.045
        case "Film 400": saturation = 0.92; contrast = 1.08
        case "Portra": saturation = 0.9; contrast = 0.96; brightness = 0.025
        case "Ektar": saturation = 1.28; contrast = 1.13
        case "Classic Chrome": saturation = 0.72; contrast = 1.12
        case "Vintage", " faded film": saturation = 0.68; contrast = 0.84; brightness = 0.055
        case "Cine Teal": saturation = 0.88; contrast = 1.12
        case "Cine Orange": saturation = 1.08; contrast = 1.16
        case "Cine Bleach": saturation = 0.48; contrast = 1.22
        case "Noir", "Mono": saturation = 0; contrast = 1.18
        case "Sepia": saturation = 0.55; contrast = 1.02
        case "Black Mist": saturation = 0.94; contrast = 0.94; brightness = 0.015
        case "Dream Glow": saturation = 1.06; contrast = 0.9; brightness = 0.035
        case "Matte": saturation = 0.88; contrast = 0.82; brightness = 0.025
        case "Drama": saturation = 0.92; contrast = 1.32
        default: break
        }
        controls.saturation = saturation
        controls.contrast = contrast
        controls.brightness = brightness
        image = controls.outputImage ?? image

        let effectName: String?
        switch name {
        case "Film 400": effectName = "CIPhotoEffectProcess"
        case "Vintage": effectName = "CIPhotoEffectTransfer"
        case " faded film": effectName = "CIPhotoEffectFade"
        case "Noir": effectName = "CIPhotoEffectNoir"
        case "Mono": effectName = "CIPhotoEffectMono"
        case "Sepia": effectName = "CISepiaTone"
        case "Kodak Gold": effectName = "CIPhotoEffectInstant"
        case "Classic Chrome": effectName = "CIPhotoEffectFade"
        case "Cine Bleach": effectName = "CIPhotoEffectTonal"
        default: effectName = nil
        }
        if let effectName, let effect = CIFilter(name: effectName) {
            effect.setValue(image, forKey: kCIInputImageKey)
            if effectName == "CISepiaTone" { effect.setValue(0.55, forKey: kCIInputIntensityKey) }
            image = effect.outputImage ?? image
        }

        if name == "Warm" || name == "Kodak Gold" || name == "Portra" {
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = image
            temp.neutral = CIVector(x: 6000, y: 0)
            temp.targetNeutral = CIVector(x: 5200, y: 0)
            image = temp.outputImage ?? image
        } else if name == "Cool" || name == "Cine Teal" {
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = image
            temp.neutral = CIVector(x: 6000, y: 0)
            temp.targetNeutral = CIVector(x: 7200, y: 0)
            image = temp.outputImage ?? image
        }

        if name == "Black Mist" || name == "Dream Glow" {
            let bloom = CIFilter.bloom()
            bloom.inputImage = image
            bloom.radius = name == "Black Mist" ? 12 : 22
            bloom.intensity = name == "Black Mist" ? 0.28 : 0.65
            image = bloom.outputImage?.cropped(to: input.extent) ?? image
        }
        if name == "Matte" || name == "Vintage" {
            let vignette = CIFilter.vignette()
            vignette.inputImage = image
            vignette.intensity = 0.45
            vignette.radius = 1.8
            image = vignette.outputImage ?? image
        }
        return image.cropped(to: input.extent)
    }

    func capturePhoto() {
        sessionQueue.async {
            guard self.configured, !self.photoOutput.connections.isEmpty, !self.movieOutput.isRecording else { return }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            settings.isHighResolutionPhotoEnabled = self.photoOutput.isHighResolutionCaptureEnabled
            if let device = self.currentInput?.device, device.position == .back,
               device.hasFlash, self.photoOutput.supportedFlashModes.contains(.off) {
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
            } else { self.session.addInput(oldInput) }
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.hdrEnabled = false
                self.updateExposureLimits(for: device)
                self.status = "Đã đổi camera"
            }
        }
    }

    func toggleRecording() {
        sessionQueue.async {
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
            else {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("NIFNAIL_\(UUID().uuidString).mov")
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }
}

extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.isCapturingPhoto = false
                self.status = "Chụp ảnh thất bại: \(error?.localizedDescription ?? "Không tạo được tệp ảnh")"
            }
            return
        }
        let processedData: Data
        if let source = CIImage(data: data) {
            let styled = applySelectedLook(to: source)
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            processedData = ciContext.jpegRepresentation(of: styled, colorSpace: colorSpace, options: [:]) ?? data
        } else { processedData = data }

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
                request.addResource(with: .photo, data: processedData, options: nil)
            }) { success, saveError in
                DispatchQueue.main.async {
                    self.isCapturingPhoto = false
                    self.status = success ? "Đã lưu ảnh với màu \(self.selectedLook)" : "Không lưu được ảnh: \(saveError?.localizedDescription ?? "Lỗi không rõ")"
                }
            }
        }
    }
}

extension CameraViewModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async { self.isRecording = true; self.status = "Đang quay…" }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            if let error { self.status = "Lỗi ghi video: \(error.localizedDescription)"; return }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async { self.status = "Chưa được cấp quyền lưu Ảnh" }
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
                }) { success, saveError in
                    DispatchQueue.main.async {
                        self.status = success ? "Đã lưu video gốc (LUT áp dụng cho ảnh)" : "Không lưu được: \(saveError?.localizedDescription ?? "Lỗi không rõ")"
                    }
                    try? FileManager.default.removeItem(at: outputFileURL)
                }
            }
        }
    }
}
