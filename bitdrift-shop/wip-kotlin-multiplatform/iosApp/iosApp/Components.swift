import SwiftUI
import Shared

// MARK: - Screen Container

struct ScreenContainer<Content: View>: View {
    let screenName: String
    let title: String
    let subtitle: String
    let step: Int
    let systemImage: String
    let color: Color
    var imageUrl: String? = nil
    var logoImageName: String? = nil
    var onBack: (() -> Void)? = nil
    var onCart: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                if let onBack = onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                    }
                    .frame(width: 48, height: 48)
                } else {
                    Spacer().frame(width: 48, height: 48)
                }

                Spacer()
                StepIndicatorView(current: step)
                Spacer()

                if let onCart = onCart {
                    Button(action: onCart) {
                        Image(systemName: "cart")
                            .font(.title2)
                    }
                    .frame(width: 48, height: 48)
                } else {
                    Spacer().frame(width: 48, height: 48)
                }
            }
            .padding(.horizontal)

            Spacer()

            // Center content
            VStack(spacing: 16) {
                if let imageUrl = imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(color.opacity(0.15)).frame(width: 120, height: 120)
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                } else if let logoImageName = logoImageName {
                    Image(logoImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 60)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .background(Color(red: 0.1, green: 0.1, blue: 0.18))
                        .cornerRadius(12)
                } else {
                    ZStack {
                        Circle().fill(color.opacity(0.15)).frame(width: 100, height: 100)
                        Image(systemName: systemImage)
                            .font(.system(size: 44))
                            .foregroundColor(color)
                    }
                }

                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text("App v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Bottom actions
            VStack(spacing: 12) {
                content()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .navigationBarHidden(true)
        .onAppear {
            ScreenLogger.logScreenView(screenName)
        }
    }
}

// MARK: - Step Indicator

struct StepIndicatorView: View {
    let current: Int
    let total: Int = 7

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...total, id: \.self) { step in
                Circle()
                    .fill(step <= current ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
            }
        }
    }
}

// MARK: - Buttons

struct PrimaryButtonView: View {
    let title: String
    let systemImage: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title).font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!enabled)
    }
}

struct SecondaryButtonView: View {
    let title: String
    let systemImage: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title).font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!enabled)
    }
}

struct SimButtonView: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.bold())
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
    }
}

// MARK: - Simulation Overlay

struct SimulationOverlayView: View {
    @ObservedObject var simulationState: SimulationState

    var body: some View {
        HStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            Text(
                simulationState.totalRuns == -1
                    ? "Simulating \(simulationState.currentRun)/∞"
                    : "Simulating \(simulationState.currentRun)/\(simulationState.totalRuns)"
            )
            .font(.subheadline.bold())
            .foregroundColor(.white)

            Spacer()

            Button(action: { simulationState.cancel() }) {
                Image(systemName: "xmark")
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

// MARK: - Product Row

struct ProductRowView: View {
    let products: [ProductCardData]
    var onProductClick: ((String) -> Void)? = nil

    var body: some View {
        if products.isEmpty { EmptyView() }
        else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(products, id: \.id) { product in
                        Button(action: { onProductClick?(product.id) }) {
                            HStack {
                                AsyncImage(url: URL(string: product.imageUrl)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.gray.opacity(0.2)
                                }
                                .frame(width: 64, height: 64)
                                .clipped()

                                VStack(alignment: .leading) {
                                    Text(product.name).font(.subheadline.bold()).lineLimit(1)
                                    Text(String(format: "$%.2f", product.price)).font(.caption)
                                }
                                .padding(.horizontal, 12)

                                Spacer()
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(radius: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }
}

// MARK: - Category Row

struct CategoryRowView: View {
    let categories: [CategoryData]
    var onCategoryClick: ((String) -> Void)? = nil

    private let categoryColors: [String: Color] = [
        "Electronics": .blue,
        "Clothing": .purple,
        "Home & Garden": .orange,
        "Sports": .green
    ]

    private let categoryIcons: [String: String] = [
        "Electronics": "iphone",
        "Clothing": "tshirt",
        "Home & Garden": "house",
        "Sports": "figure.run"
    ]

    var body: some View {
        if categories.isEmpty { EmptyView() }
        else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(categories, id: \.name) { cat in
                        let color = categoryColors[cat.name] ?? .gray
                        let icon = categoryIcons[cat.name] ?? "list.bullet"

                        Button(action: { onCategoryClick?(cat.name) }) {
                            HStack(spacing: 12) {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundColor(color)
                                    .frame(width: 32)

                                VStack(alignment: .leading) {
                                    Text(cat.name).font(.subheadline.bold())
                                    Text("\(cat.productCount) items").font(.caption).foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(color)
                            }
                            .padding(12)
                            .background(color.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }
}

// MARK: - Swift Data Models (mapped from Shared)

struct ProductCardData: Identifiable {
    let id: String
    let name: String
    let price: Double
    let imageUrl: String
    let category: String
    let brand: String
}

struct CategoryData {
    let name: String
    let productCount: Int
}
