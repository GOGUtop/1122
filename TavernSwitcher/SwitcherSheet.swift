import SwiftUI

struct SwitcherSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.025, green: 0.055, blue: 0.10), Color(red: 0.06, green: 0.09, blue: 0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 13) {
                        ForEach(TavernEndpoint.all) { endpoint in
                            Button {
                                appState.open(endpoint)
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: endpoint.icon)
                                        .font(.system(size: 21, weight: .black))
                                        .frame(width: 44, height: 44)
                                        .background(.white.opacity(0.12), in: Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(endpoint.title)
                                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                                        Text(endpoint.url.absoluteString)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white.opacity(0.58))
                                    }
                                    Spacer()
                                    if appState.activeEndpoint == endpoint {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.white.opacity(0.44))
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(16)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                                        .stroke(.white.opacity(appState.activeEndpoint == endpoint ? 0.38 : 0.16))
                                )
                            }
                            .buttonStyle(PressableButtonStyle())
                        }

                        Button(role: .destructive) {
                            appState.resetWebData()
                            dismiss()
                        } label: {
                            Label("清空缓存并重新加载", systemImage: "trash")
                                .font(.system(size: 16, weight: .heavy))
                                .frame(maxWidth: .infinity)
                                .padding(15)
                                .background(Color.red.opacity(0.20), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.12)))
                        }
                        .foregroundStyle(.red)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("切换云洞")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
