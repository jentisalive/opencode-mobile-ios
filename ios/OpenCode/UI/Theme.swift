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
            // Original CloudUi.kt geometry, in its 748 × 428 coordinate system.
            let scale = size.width / 748
            func rect(_ x: CGFloat, _ y: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ fill: Color) {
                context.fill(Path(CGRect(x: x * scale, y: y * scale, width: (x1 - x) * scale, height: (y1 - y) * scale)), with: .color(fill))
            }
            rect(0, 113, 748, 428, color)
            rect(152, 0, 635, 114, color)
            if eyes {
                let shade = Color(hex: 0xBABABC)
                rect(565, 0, 635, 113, shade)
                rect(635, 113, 704, 193, shade)
                rect(0, 213, 62, 428, shade)
                rect(62, 333, 127, 428, shade)
                rect(245, 110, 313, 308, Color(hex: 0x18181A))
                rect(430, 110, 498, 308, Color(hex: 0x18181A))
            }
        }
        .aspectRatio(748.0 / 428.0, contentMode: .fit)
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
