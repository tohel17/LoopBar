import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings: Settings
    let onComplete: () -> Void

    @State private var step = Step.welcome
    @State private var isFinishing = false

    private enum Step: Int, CaseIterable {
        case welcome
        case howItWorks
        case tools
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator

            Group {
                switch step {
                case .welcome:
                    welcomePage
                case .howItWorks:
                    howItWorksPage
                case .tools:
                    toolsPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 58)

            footer
        }
        .frame(width: 760, height: 570)
        .background {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.blue.opacity(0.055)
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.22))
                    .frame(width: item == step ? 28 : 8, height: 8)
                    .animation(.easeOut(duration: 0.18), value: step)
            }
        }
        .padding(.top, 25)
        .accessibilityLabel("Setup step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    private var welcomePage: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.black)
                    .frame(width: 118, height: 82)
                    .shadow(color: .blue.opacity(0.22), radius: 24, y: 10)
                HStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange)
                }
                .font(.system(size: 24, weight: .semibold))
            }

            VStack(spacing: 10) {
                Text("Keep every coding agent in sight")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("LoopBar turns your Mac's notch into a quiet status center for local coding work.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
                    .lineSpacing(3)
            }

            Label("No account or API key required", systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.green.opacity(0.1), in: Capsule())
        }
    }

    private var howItWorksPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("How LoopBar works")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("A quick glance tells you what is running and what needs you.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                walkthroughCard(
                    icon: "eye.fill",
                    color: .purple,
                    title: "Watches locally",
                    detail: "Reads recent task status from supported tools on this Mac."
                )
                walkthroughCard(
                    icon: "capsule.inset.filled",
                    color: .blue,
                    title: "Shows the signal",
                    detail: "The notch displays running work and items needing attention."
                )
                walkthroughCard(
                    icon: "arrow.up.forward.app.fill",
                    color: .orange,
                    title: "Takes you back",
                    detail: "Expand LoopBar and select a task to return to its source app."
                )
            }

            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                Text("LoopBar is read-only. Your prompts and project data stay on your Mac.")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var toolsPage: some View {
        VStack(spacing: 18) {
            VStack(spacing: 7) {
                Text("Which coding tools do you use?")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Enable only the IDE and agents you want LoopBar to monitor. You can change these later in Settings.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                toolOption(
                    title: "Cursor",
                    detail: "IDE composer activity",
                    icon: "cursorarrow.rays",
                    color: .purple,
                    isEnabled: $settings.cursorEnabled
                )
                toolOption(
                    title: "Codex",
                    detail: "Local app and CLI task activity",
                    icon: "sparkles",
                    color: .blue,
                    isEnabled: $settings.codexEnabled
                )
                toolOption(
                    title: "Claude Code",
                    detail: "Terminal session activity",
                    icon: "terminal.fill",
                    color: .orange,
                    isEnabled: $settings.claudeEnabled
                )
            }

            Toggle(isOn: $settings.notificationsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify me when work finishes or needs attention")
                        .font(.system(size: 13, weight: .semibold))
                    Text("macOS will ask for notification permission when setup finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 14)
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    move(to: step.rawValue - 1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(isFinishing)
            }

            Spacer()

            Button(step == .tools ? "Start using LoopBar" : "Continue") {
                if step == .tools {
                    guard !isFinishing else { return }
                    isFinishing = true
                    onComplete()
                } else {
                    move(to: step.rawValue + 1)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isFinishing)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 22)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func walkthroughCard(icon: String, color: Color, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(title)
                .font(.system(size: 14, weight: .bold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .padding(16)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func toolOption(
        title: String,
        detail: String,
        icon: String,
        color: Color,
        isEnabled: Binding<Bool>
    ) -> some View {
        Button {
            isEnabled.wrappedValue.toggle()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(isEnabled.wrappedValue ? "Enabled" : "Disabled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isEnabled.wrappedValue ? color : Color.secondary)
                Image(systemName: isEnabled.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isEnabled.wrappedValue ? color : Color.secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isEnabled.wrappedValue ? color.opacity(0.075) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isEnabled.wrappedValue ? color.opacity(0.3) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isEnabled.wrappedValue ? "Enabled" : "Disabled")
    }

    private func move(to rawValue: Int) {
        guard let nextStep = Step(rawValue: rawValue) else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            step = nextStep
        }
    }
}
