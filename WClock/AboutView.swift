import SwiftUI

/// Weather credit and legal link, as the weather provider's terms require.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var attribution: WeatherAttribution?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("WClock")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                Text("A simple bedside clock.")
                    .foregroundStyle(.secondary)

                if let a = attribution {
                    VStack(spacing: 12) {
                        if let mark = a.markURL {
                            AsyncImage(url: mark) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                                .frame(height: 20)
                        } else {
                            Text("Weather data by \(a.name)").foregroundStyle(.secondary)
                        }
                        Link("Data sources & legal", destination: a.legalURL)
                    }
                    .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar { Button("Done") { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .task { attribution = await WeatherProvider.attribution() }
    }
}
