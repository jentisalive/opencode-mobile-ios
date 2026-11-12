import SwiftUI

struct MessageText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MessageBlock.parse(text).enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .text:
                    Text(LocalizedStringKey(block.content)).textSelection(.enabled)
                case .code(let language):
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(language.isEmpty ? "Code" : language).font(.caption.monospaced()).foregroundStyle(Palette.dim)
                            Spacer()
                            Button { UIPasteboard.general.string = block.content } label: { Label("Copy", systemImage: "doc.on.doc").font(.caption) }
                        }.padding(12)
                        Divider()
                        ScrollView(.horizontal) {
                            Text(block.content).font(.system(.callout, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false).padding(12)
                        }
                    }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}
