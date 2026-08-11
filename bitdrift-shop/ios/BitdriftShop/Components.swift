import SwiftUI

// MARK: - Palette

/// Screen accent colours, matching the Android app's per-screen hues.
enum Palette {
    static let blue = Color(red: 0.13, green: 0.59, blue: 0.95)     // 0xFF2196F3
    static let purple = Color(red: 0.61, green: 0.15, blue: 0.69)   // 0xFF9C27B0
    static let orange = Color(red: 1.00, green: 0.60, blue: 0.00)   // 0xFFFF9800
    static let yellow = Color(red: 1.00, green: 0.92, blue: 0.23)   // 0xFFFFEB3B
    static let green = Color(red: 0.30, green: 0.69, blue: 0.31)    // 0xFF4CAF50
    static let cyan = Color(red: 0.00, green: 0.74, blue: 0.83)     // 0xFF00BCD4
    static let teal = Color(red: 0.00, green: 0.90, blue: 0.74)     // 0xFF00E5BD
    static let pink = Color(red: 0.91, green: 0.12, blue: 0.39)     // 0xFFE91E63
    static let indigo = Color(red: 0.25, green: 0.32, blue: 0.71)   // 0xFF3F51B5
    static let seafoam = Color(red: 0.00, green: 0.59, blue: 0.53)  // 0xFF009688
    static let red = Color(red: 0.90, green: 0.22, blue: 0.21)      // 0xFFE53935
    static let deepRed = Color(red: 0.83, green: 0.18, blue: 0.18)  // 0xFFD32F2F
    static let brown = Color(red: 0.47, green: 0.33, blue: 0.28)    // 0xFF795548
    static let violet = Color(red: 0.67, green: 0.28, blue: 0.74)   // 0xFFAB47BC
    static let amber = Color(red: 1.00, green: 0.44, blue: 0.00)    // 0xFFFF6F00
    static let slate = Color(red: 0.38, green: 0.49, blue: 0.55)    // 0xFF607D8B
    static let crimson = Color(red: 0.96, green: 0.26, blue: 0.21)  // 0xFFF44336
    /// Card background behind the (white) bitdrift logo.
    static let logoBackdrop = Color(red: 0.10, green: 0.10, blue: 0.18) // 0xFF1A1A2E
}

// MARK: - Screen container

/// Shared page chrome: step indicator, hero (logo / product image / icon),
/// title, subtitle, and a bottom action stack.
///
/// Note that this does *not* log the screen view — `Navigator` does that
/// centrally, so simulator-driven navigation logs identically to user taps.
struct ScreenContainer<Content: View>: View {
    let title: String
    let subtitle: String
    let step: Int
    let systemImage: String
    let color: Color
    var imageURL: String?
    var showLogo = false
    var latestSDKVersion: String?
    var onBack: (() -> Void)?
    var onCart: (() -> Void)?
    @ViewBuilder var content: () -> Content

    private var isSDKOutdated: Bool {
        guard let latestSDKVersion else { return false }
        return latestSDKVersion != AppConfig.captureSDKVersion
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Group {
                    if let onBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left").font(.title3)
                        }
                        .accessibilityLabel("Back")
                    }
                }
                .frame(width: 48, height: 48)

                Spacer()
                StepIndicator(current: step)
                Spacer()

                Group {
                    if let onCart {
                        Button(action: onCart) {
                            Image(systemName: "cart").font(.title3)
                        }
                        .accessibilityLabel("Cart")
                    }
                }
                .frame(width: 48, height: 48)
            }

            Spacer(minLength: 8)

            VStack(spacing: 16) {
                hero

                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Screens with the logo group the version info above; everything
                // else shows the app version alone down here.
                if !showLogo {
                    Text("App v\(AppConfig.appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 12) {
                content()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var hero: some View {
        if showLogo {
            VStack(spacing: 6) {
                Image("BitdriftLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(Palette.logoBackdrop, in: RoundedRectangle(cornerRadius: 12))

                Text("SDK v\(AppConfig.captureSDKVersion)\(isSDKOutdated ? " ⚑" : "")")
                    .font(.caption)
                    .foregroundStyle(isSDKOutdated ? Palette.orange : Color.secondary)

                if isSDKOutdated, let latestSDKVersion {
                    Text("v\(latestSDKVersion) available")
                        .font(.caption2)
                        .foregroundStyle(Palette.orange.opacity(0.75))
                }

                Text("App v\(AppConfig.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(color.opacity(0.15))
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 100, height: 100)
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - Step indicator

struct StepIndicator: View {
    let current: Int
    var total: Int = 7

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...total, id: \.self) { step in
                Circle()
                    .fill(step <= current ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    let systemImage: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(!enabled)
    }
}

struct SecondaryButton: View {
    let title: String
    let systemImage: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(!enabled)
    }
}

struct SimButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Compact toggle-style button used across the Advanced screen's fault grid.
struct ToggleChipButton: View {
    let title: String
    let isOn: Bool
    var onColor: Color
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(isOn ? onColor : Palette.brown)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

// MARK: - Simulation overlay

struct SimulationOverlay: View {
    @ObservedObject var sim: SimulationManager

    private var loopFlagStatus: String {
        let flags = [
            sim.crashLoopEnabled ? "Crash" : nil,
            sim.appHangEnabled ? "Hang" : nil,
            sim.forceQuitEnabled ? "Quit" : nil,
        ].compactMap { $0 }
        return flags.isEmpty ? "No flags" : flags.joined(separator: " + ") + " enabled"
    }

    private var hangEligibilityNote: String {
        sim.appHangEnabled && sim.activeVariant != .variantA ? " (Variant A only)" : ""
    }

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(sim.isInfiniteMode
                     ? "Simulating \(sim.currentRun)/∞"
                     : "Simulating \(sim.currentRun)/\(sim.totalRuns)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(sim.activeVariant.label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text(loopFlagStatus + hangEligibilityNote)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            Button {
                sim.cancel()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.8))
            }
            .accessibilityLabel("Cancel simulation")
        }
        .padding(16)
        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
}

// MARK: - Fast crash splash

/// Full-screen and opaque by design: fast crash mode intentionally skips all
/// navigation and UI, so without this there is no on-device signal telling apart
/// "about to crash in ~300ms–2s" from "the app is stuck".
struct FastCrashModeSplash: View {
    let status: SimulationManager.FastCrashStatus?
    var awaitingBackground = false

    var body: some View {
        ZStack {
            Palette.logoBackdrop.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Palette.crimson)

                Text("FAST CRASH MODE")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                if let status {
                    if status.oomOnly {
                        Text("OOM ONLY")
                            .font(.caption.bold())
                            .foregroundStyle(Palette.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Palette.orange.opacity(0.15), in: Capsule())
                    }
                    Text("Next crash: \(status.kind)")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("(\(status.context))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))

                    if awaitingBackground {
                        // Nothing is stuck — the background half of the sweep only
                        // fires once the app actually leaves the foreground.
                        Label("Press Home to background the app", systemImage: "hand.point.up.left")
                            .font(.caption)
                            .foregroundStyle(Palette.orange)
                            .padding(.top, 4)
                    }
                } else {
                    ProgressView().tint(.white)
                    Text("Preparing next crash…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Text("scripts/watchdog.sh --stop  to stop")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
    }
}

// MARK: - Product / category lists

struct ProductImageRow: View {
    let products: [JSON]
    var onProductTap: (String) -> Void = { _ in }

    var body: some View {
        if !products.isEmpty {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(products.enumerated()), id: \.offset) { _, product in
                        Button {
                            onProductTap(product.str("id"))
                        } label: {
                            HStack(spacing: 0) {
                                AsyncImage(url: URL(string: product.str("image_url"))) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.gray.opacity(0.2)
                                }
                                .frame(width: 64, height: 64)
                                .clipped()

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.str("name"))
                                        .font(.subheadline.bold())
                                        .lineLimit(1)
                                    Text(money(product.num("price")))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)

                                Spacer(minLength: 0)
                            }
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }
}

struct CategoryRow: View {
    let categories: [JSON]
    var onCategoryTap: (String) -> Void = { _ in }

    private static let colors: [String: Color] = [
        "Electronics": Palette.blue,
        "Clothing": Palette.purple,
        "Home & Garden": Palette.orange,
        "Sports": Palette.green,
    ]

    private static let icons: [String: String] = [
        "Electronics": "iphone",
        "Clothing": "tshirt",
        "Home & Garden": "house",
        "Sports": "figure.run",
    ]

    var body: some View {
        if !categories.isEmpty {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(categories.enumerated()), id: \.offset) { _, category in
                        let name = category.str("name")
                        let color = Self.colors[name] ?? .gray
                        Button {
                            onCategoryTap(name)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: Self.icons[name] ?? "list.bullet")
                                    .font(.title3)
                                    .foregroundStyle(color)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name).font(.subheadline.bold())
                                    Text("\(category.int("product_count")) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right").foregroundStyle(color)
                            }
                            .padding(12)
                            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }
}

struct RecommendedSection: View {
    let recommendations: [(product: JSON, score: Double)]
    let onProductTap: (String) -> Void

    var body: some View {
        if !recommendations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recommended for You")
                    .font(.subheadline.bold())

                ForEach(Array(recommendations.prefix(3).enumerated()), id: \.offset) { _, item in
                    Button {
                        onProductTap(item.product.str("id"))
                    } label: {
                        HStack(spacing: 10) {
                            AsyncImage(url: URL(string: item.product.str("image_url"))) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.product.str("name"))
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                Text("\(Int(item.score * 100))% match")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
