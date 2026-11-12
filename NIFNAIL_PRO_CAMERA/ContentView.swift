import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NIFNAIL PRO").font(.headline).bold()
                        Text("CAMERA").font(.caption2).tracking(3).foregroundStyle(.gray)
                    }
                    Spacer()
                    Text(camera.hdrEnabled ? "VIDEO HDR ON" : "VIDEO HDR OFF")
                        .font(.caption).bold()
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(camera.hdrEnabled ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .padding(.horizontal)

                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .bottom) {
                        Text(camera.status)
                            .font(.caption).padding(8)
                            .background(.black.opacity(0.55))
                            .clipShape(Capsule()).padding(12)
                    }
                    .padding(.horizontal)

                VStack(spacing: 10) {
                    HStack {
                        Text("Bù sáng").font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f EV", camera.exposureBias))
                            .monospacedDigit().foregroundStyle(.yellow)
                    }
                    Slider(value: Binding(
                        get: { Double(camera.exposureBias) },
                        set: { camera.setBias(Float($0)) }
                    ), in: -2...2, step: 0.1)
                    .tint(.yellow)

                    Toggle("Phơi sáng thủ công", isOn: Binding(
                        get: { camera.isManualExposure },
                        set: { camera.setManualExposure($0) }
                    ))
                    .tint(.yellow)

                    if camera.isManualExposure {
                        HStack {
                            Text("ISO")
                            Slider(value: Binding(
                                get: { Double(camera.iso) },
                                set: { camera.updateManualExposure(iso: Float($0)) }
                            ), in: camera.isoRange)
                            Text("\(Int(camera.iso))").monospacedDigit().frame(width: 48)
                        }
                        HStack {
                            Text("Màn trập")
                            Slider(value: Binding(
                                get: { camera.shutterSeconds },
                                set: { camera.updateManualExposure(shutter: $0) }
                            ), in: camera.shutterRange)
                            Text(String(format: "1/%.0f", 1.0 / camera.shutterSeconds))
                                .monospacedDigit().frame(width: 60)
                        }
                    }
                }
                .padding(.horizontal, 22)

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
                            Image(systemName: "camera.fill")
                                .font(.title2).foregroundStyle(.black)
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
                .padding(.bottom, 10)
            }
            .foregroundStyle(.white)
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
}
