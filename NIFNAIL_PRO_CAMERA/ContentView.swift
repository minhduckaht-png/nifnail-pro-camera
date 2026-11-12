import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                header
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .bottom) {
                        Text(camera.status)
                            .font(.caption).padding(8)
                            .background(.black.opacity(0.55))
                            .clipShape(Capsule()).padding(12)
                    }
                    .padding(.horizontal)

                ScrollView {
                    VStack(spacing: 12) {
                        exposureControls
                        whiteBalanceControls
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 280)

                captureControls
            }
            .foregroundStyle(.white)
            .padding(.top, 8)
        }
        .alert("Quyền truy cập", isPresented: Binding(
            get: { camera.permissionMessage != nil },
            set: { if !$0 { camera.permissionMessage = nil } }
        )) {
            Button("Đóng", role: .cancel) { camera.permissionMessage = nil }
        } message: {
            Text(camera.permissionMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("NIFNAIL PRO").font(.headline).bold()
                Text("CAMERA").font(.caption2).tracking(3).foregroundStyle(.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("HDR ẢNH").font(.caption).bold().foregroundStyle(.green)
                Text("ƯU TIÊN CHI TIẾT").font(.system(size: 9)).foregroundStyle(.gray)
            }
        }
        .padding(.horizontal)
    }

    private var exposureControls: some View {
        VStack(spacing: 9) {
            HStack {
                Text("PHƠI SÁNG").font(.caption).bold().foregroundStyle(.yellow)
                Spacer()
                Text(String(format: "%.1f EV", camera.exposureBias)).monospacedDigit()
            }
            Slider(value: Binding(
                get: { Double(camera.exposureBias) },
                set: { camera.setBias(Float($0)) }
            ), in: -2...2, step: 0.1).tint(.yellow)

            Toggle("ISO / tốc độ màn trập thủ công", isOn: Binding(
                get: { camera.isManualExposure },
                set: { camera.setManualExposure($0) }
            )).tint(.yellow)

            if camera.isManualExposure {
                VStack(spacing: 4) {
                    HStack {
                        Text("ISO")
                        Spacer()
                        Text("\(Int(camera.iso)) / tối đa \(Int(camera.isoRange.upperBound))")
                            .monospacedDigit().foregroundStyle(.yellow)
                    }
                    Slider(value: Binding(
                        get: { Double(camera.iso) },
                        set: { camera.updateManualExposure(iso: Float($0)) }
                    ), in: camera.isoRange).tint(.yellow)

                    HStack {
                        Text("Tốc độ")
                        Spacer()
                        Text(shutterLabel(camera.shutterSeconds)).monospacedDigit().foregroundStyle(.yellow)
                    }
                    Slider(value: Binding(
                        get: { camera.shutterSeconds },
                        set: { camera.updateManualExposure(shutter: $0) }
                    ), in: camera.shutterRange).tint(.yellow)
                }
            }
        }
        .font(.subheadline)
    }

    private var whiteBalanceControls: some View {
        VStack(spacing: 8) {
            Divider().overlay(.white.opacity(0.2))
            HStack {
                Text("CÂN BẰNG TRẮNG").font(.caption).bold().foregroundStyle(.yellow)
                Spacer()
                Text(camera.isManualWhiteBalance ? "MANUAL" : "AUTO")
                    .font(.caption2).foregroundStyle(.gray)
            }
            Toggle("Chỉnh WB thủ công", isOn: Binding(
                get: { camera.isManualWhiteBalance },
                set: { camera.setManualWhiteBalance($0) }
            )).tint(.yellow)

            if camera.isManualWhiteBalance {
                HStack {
                    Text("Nhiệt độ")
                    Spacer()
                    Text("\(Int(camera.whiteBalanceTemperature)) K").monospacedDigit().foregroundStyle(.yellow)
                }
                Slider(value: Binding(
                    get: { camera.whiteBalanceTemperature },
                    set: { camera.updateWhiteBalance(temperature: $0) }
                ), in: 2500...10000).tint(.orange)

                HStack {
                    Text("Tint")
                    Spacer()
                    Text(String(format: "%.0f", camera.whiteBalanceTint)).monospacedDigit().foregroundStyle(.yellow)
                }
                Slider(value: Binding(
                    get: { camera.whiteBalanceTint },
                    set: { camera.updateWhiteBalance(tint: $0) }
                ), in: -150...150).tint(.purple)
            }
        }
        .font(.subheadline)
    }

    private var captureControls: some View {
        HStack {
            Button { camera.switchCamera() } label: {
                Image(systemName: "camera.rotate").font(.title2)
                    .frame(width: 54, height: 54)
                    .background(.white.opacity(0.12)).clipShape(Circle())
            }
            .disabled(camera.isRecording || camera.isCapturingPhoto)

            Spacer()

            Button { camera.capturePhoto() } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(.white).frame(width: 58, height: 58)
                    Image(systemName: "camera.fill").font(.title2).foregroundStyle(.black)
                }
            }
            .disabled(camera.isRecording || camera.isCapturingPhoto)

            Spacer()

            Button { camera.toggleRecording() } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 58, height: 58)
                    Circle().fill(.red)
                        .frame(width: camera.isRecording ? 25 : 42,
                               height: camera.isRecording ? 25 : 42)
                }
            }
            .disabled(camera.isCapturingPhoto)
        }
        .padding(.horizontal, 34)
        .padding(.bottom, 8)
    }

    private func shutterLabel(_ seconds: Double) -> String {
        seconds >= 1 ? String(format: "%.1fs", seconds) : String(format: "1/%.0f", 1 / seconds)
    }
}
