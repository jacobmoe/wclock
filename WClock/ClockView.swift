import SwiftUI

private struct Palette {
    let background: Color
    let primary: Color
    let secondary: Color

    // Deep charcoal with soft warm-white text.
    static let day = Palette(
        background: Color(red: 0.07, green: 0.07, blue: 0.08),
        primary: Color(red: 0.95, green: 0.93, blue: 0.88),
        secondary: Color(red: 0.95, green: 0.93, blue: 0.88).opacity(0.55))
    // Dim warm amber on black: easy on the eyes and doesn't light up the room.
    static let night = Palette(
        background: .black,
        primary: Color(red: 0.62, green: 0.30, blue: 0.14),
        secondary: Color(red: 0.62, green: 0.30, blue: 0.14).opacity(0.6))
}

struct ClockView: View {
    @StateObject private var model = ClockModel()
    @Environment(\.scenePhase) private var scenePhase

    private static let uses12Hour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false

    private var palette: Palette { model.isNight ? .night : .day }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width * 0.24, geo.size.height * 0.45)
            VStack(spacing: size * 0.12) {
                Spacer()
                TimelineView(.everyMinute) { ctx in
                    VStack(spacing: size * 0.05) {
                        timeText(ctx.date, size: size)
                        Text(ctx.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.system(size: size * 0.16, weight: .light, design: .rounded))
                            .foregroundStyle(palette.secondary)
                    }
                }
                weatherRow(size: size)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.background.ignoresSafeArea())
        .overlay(alignment: .topTrailing) { optionsMenu }
        .contentShape(Rectangle())
        .onTapGesture { if model.isNight && model.dimAtNight { model.toggleBoost() } }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onChange(of: scenePhase, initial: true) { _, phase in
            phase == .active ? model.start() : model.stop()
        }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Appearance", selection: $model.appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            Picker("Temperature", selection: $model.unit) {
                ForEach(TempUnit.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Dim screen at night", isOn: $model.dimAtNight)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.secondary.opacity(0.7))
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
        }
        .padding(16)
    }

    private func timeText(_ date: Date, size: CGFloat) -> some View {
        let twelve = Self.uses12Hour
        let minutes = date.minuteOfDay
        let h = minutes / 60
        let shownHour = twelve ? (h % 12 == 0 ? 12 : h % 12) : h
        let digits = String(format: twelve ? "%d:%02d" : "%02d:%02d", shownHour, minutes % 60)
        return HStack(alignment: .firstTextBaseline, spacing: size * 0.04) {
            Text(digits)
                .font(.system(size: size, weight: .thin, design: .rounded))
                .monospacedDigit()
            if twelve {
                Text(h < 12 ? "AM" : "PM")
                    .font(.system(size: size * 0.18, weight: .light, design: .rounded))
                    .foregroundStyle(palette.secondary)
            }
        }
        .foregroundStyle(palette.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    private func weatherRow(size: CGFloat) -> some View {
        ZStack {
            if let w = model.weather {
                HStack(spacing: size * 0.08) {
                    Image(systemName: w.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: size * 0.2, weight: .light))
                    Text("\(model.unit.degrees(fromCelsius: w.temperature))°")
                        .font(.system(size: size * 0.2, weight: .light, design: .rounded))
                    Text("\(w.summary)  ·  H \(model.unit.degrees(fromCelsius: w.high))°  L \(model.unit.degrees(fromCelsius: w.low))°")
                        .font(.system(size: size * 0.11, weight: .light, design: .rounded))
                        .foregroundStyle(palette.secondary)
                }
                .foregroundStyle(palette.primary)
                .transition(.opacity)
            }
        }
        .frame(height: size * 0.28)  // reserved so the clock doesn't shift when weather appears
        .animation(.easeIn(duration: 0.6), value: model.weather != nil)
    }
}
