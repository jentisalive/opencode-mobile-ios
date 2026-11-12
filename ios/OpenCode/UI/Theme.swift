import SwiftUI

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
enum Palette {
    static let background = Color(hex: 0x0B0C0E)
    static let surface = Color(hex: 0x141619)
    static let high = Color(hex: 0x1D2024)
    static let text = Color(hex: 0xE4E7EB)
    static let dim = Color(hex: 0x8B9199)
    static let border = Color(hex: 0x25292E)
    static let accent = Color(hex: 0x97AAC2)
}

struct PixelCloud: View {
    var eyes = true
    var color = Color.white
    var body: some View {
        Canvas { context, size in
            let unit = size.width / 12
            let rows = ["000111111000", "000111111000", "011111111110", "011101101111", "111101101111", "111101101111", "111111111111"]
            for (y, row) in rows.enumerated() {
                for (x, value) in row.enumerated() where value == "1" || (!eyes && y >= 3 && x >= 1 && x <= 10) {
                    context.fill(Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit + 0.2, height: unit + 0.2)), with: .color(color))
                }
            }
        }
        .aspectRatio(12 / 7, contentMode: .fit)
        .accessibilityLabel("cl0udly")
    }
}

struct CloudBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top) {
                PixelCloud(eyes: false, color: Color(hex: 0x1A202B)).frame(width: 140).offset(x: -30, y: 30)
                Spacer()
                PixelCloud(eyes: false, color: Color(hex: 0x1A202B)).frame(width: 140).offset(x: 30, y: 55)
            }.frame(width: geo.size.width)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct RoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 46, height: 46).background(Palette.surface, in: Circle()).overlay(Circle().stroke(Palette.border)) }
            .accessibilityLabel(label).buttonStyle(.plain)
    }
}
