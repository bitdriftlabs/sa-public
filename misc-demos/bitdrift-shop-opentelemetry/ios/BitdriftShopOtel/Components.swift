import Capture
import SwiftUI

// Category color/icon mapping -- aligned with OTel Demo Telescope Store catalog. Mirrors
// `Components.kt`'s `categoryColors`/`categoryIcons`.
private let categoryColors: [String: Color] = [
    "Telescopes": Color(red: 0x3F / 255, green: 0x51 / 255, blue: 0xB5 / 255),
    "Accessories": Color(red: 0x61 / 255, green: 0x96 / 255, blue: 0xF3 / 255),
    "Binoculars": Color(red: 0x00 / 255, green: 0x96 / 255, blue: 0x88 / 255),
    "Flashlights": Color(red: 0xFF / 255, green: 0x98 / 255, blue: 0x00 / 255),
    "Books": Color(red: 0x9C / 255, green: 0x27 / 255, blue: 0xB0 / 255),
    "Assembly": Color(red: 0x60 / 255, green: 0x7D / 255, blue: 0x8B / 255),
    "Travel": Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255),
    "Products": Color(red: 0x79 / 255, green: 0x55 / 255, blue: 0x48 / 255),
]

private let categoryIcons: [String: String] = [
    "Telescopes": "star.fill",
    "Accessories": "hammer.fill",
    "Binoculars": "magnifyingglass",
    "Flashlights": "exclamationmark.triangle.fill",
    "Books": "info.circle.fill",
    "Assembly": "gearshape.fill",
    "Travel": "mappin.circle.fill",
    "Products": "cart.fill",
]

// MARK: - Reusable Components

struct StepIndicator: View {
    let current: Int
    var total: Int = 7

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1 ... total, id: \.self) { step in
                Circle()
                    .fill(step <= current ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.vertical, 8)
    }
}

struct ScreenContainer<Content: View>: View {
    let screenName: String
    let title: String
    let subtitle: String
    let step: Int
    let systemIcon: String
    let color: Color
    var imageURL: String?
    var imageIsLogo = false
    var showSdkVersion = false
    var latestSdkVersion: String?
    var onBack: (() -> Void)?
    var onCart: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Group {
                    if let onBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.backward")
                        }
                    }
                }
                .frame(width: 48, height: 48)
                Spacer()
                StepIndicator(current: step)
                Spacer()
                Group {
                    if let onCart {
                        Button(action: onCart) {
                            Image(systemName: "cart")
                        }
                    }
                }
                .frame(width: 48, height: 48)
            }

            Spacer()

            VStack(spacing: 16) {
                if imageIsLogo, let imageURL {
                    // A bundled asset (e.g. "AppLogo"), not a remote URL -- AsyncImage only
                    // handles the latter.
                    Image(imageURL)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 84)
                        .padding(.horizontal, 8)
                } else if let imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                } else {
                    ZStack {
                        Circle().fill(color.opacity(0.15)).frame(width: 100, height: 100)
                        Image(systemName: systemIcon).font(.system(size: 40)).foregroundStyle(color)
                    }
                }

                if showSdkVersion {
                    let isOutdated = latestSdkVersion != nil && latestSdkVersion != Capture.Logger.sdkVersion
                    VStack(spacing: 2) {
                        Text("SDK v\(Capture.Logger.sdkVersion)\(isOutdated ? " \u{2691}" : "")")
                            .font(.caption)
                            .foregroundStyle(isOutdated ? Color.orange : .secondary)
                        if isOutdated, let latestSdkVersion {
                            Text("v\(latestSdkVersion) available")
                                .font(.caption2)
                                .foregroundStyle(Color.orange.opacity(0.75))
                        }
                        Text("Capture.xcframework (local)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Rust span builder: \(AppConfig.aarHasRustSpanBuilder ? "yes" : "NO (old build?)")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("App v\(AppConfig.appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(title).font(.title2).fontWeight(.bold)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Spacer()

            VStack(spacing: 12) {
                content
            }
        }
        .padding(24)
        .onAppear { ScreenLogger.logScreenView(screenName) }
    }
}

struct PrimaryButton: View {
    let title: String
    let systemIcon: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemIcon)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!enabled)
    }
}

struct SecondaryButton: View {
    let title: String
    let systemIcon: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemIcon)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
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
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
    }
}

struct SimulationOverlay: View {
    @ObservedObject var simulationManager: SimulationManager

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().tint(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(simulationManager.isInfiniteMode
                    ? "Simulating \(simulationManager.currentRun)/\u{221E}"
                    : "Simulating \(simulationManager.currentRun)/\(simulationManager.totalRuns)")
                    .font(.subheadline).fontWeight(.bold).foregroundStyle(.white)
                Text(simulationManager.activeVariant.label)
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button(action: { simulationManager.cancel() }) {
                Image(systemName: "xmark").foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(16)
    }
}

struct ProductImageRow: View {
    let products: [JSONObject]
    var onProductClick: (String) -> Void = { _ in }

    var body: some View {
        if !products.isEmpty {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(products.enumerated()), id: \.offset) { _, product in
                        let productId = product.optString("id")
                        Button(action: { onProductClick(productId) }) {
                            HStack {
                                AsyncImage(url: URL(string: product.optString("image_url"))) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.gray.opacity(0.2) }
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading) {
                                    Text(product.optString("name")).fontWeight(.bold).lineLimit(1)
                                    Text(String(format: "$%.2f", product.optDouble("price"))).font(.caption)
                                }
                                .padding(.horizontal, 12)
                                Spacer()
                            }
                            .padding(8)
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
    let categories: [JSONObject]
    var onCategoryClick: (String) -> Void = { _ in }

    var body: some View {
        if !categories.isEmpty {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(categories.enumerated()), id: \.offset) { _, cat in
                        let name = cat.optString("name")
                        let count = cat.optInt("product_count")
                        let color = categoryColors[name] ?? .gray
                        let icon = categoryIcons[name] ?? "list.bullet"
                        Button(action: { onCategoryClick(name) }) {
                            HStack {
                                Image(systemName: icon).foregroundStyle(color).frame(width: 32, height: 32)
                                VStack(alignment: .leading) {
                                    Text(name).fontWeight(.bold)
                                    Text("\(count) items").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(color)
                            }
                            .padding(12)
                            .background(color.opacity(0.15))
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

struct RecommendedSection: View {
    let recommendations: [(JSONObject, Double)]
    let onProductClick: (String) -> Void

    var body: some View {
        if !recommendations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recommended for You").font(.subheadline).fontWeight(.bold)
                ForEach(Array(recommendations.prefix(3).enumerated()), id: \.offset) { _, pair in
                    let (product, score) = pair
                    Button(action: { onProductClick(product.optString("id")) }) {
                        HStack {
                            AsyncImage(url: URL(string: product.optString("image_url"))) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.gray.opacity(0.2) }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading) {
                                Text(product.optString("name")).font(.caption).fontWeight(.bold).lineLimit(1)
                                Text("\(Int(score * 100))% match").font(.caption2).foregroundStyle(Color.accentColor)
                            }
                            .padding(.leading, 10)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

