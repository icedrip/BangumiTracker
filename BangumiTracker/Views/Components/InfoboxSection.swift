import SwiftUI

struct InfoboxSection: View {
    let infobox: [InfoboxItem]

    var body: some View {
        DetailSectionCard(spacing: 8) {
            Text("信息")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            // Grid auto-sizes the key column to the widest key, so a 5-char
            // key like "简体中文名" no longer wraps (the old fixed 60pt frame
            // forced it to two lines). Left-aligned keys also avoid the
            // ragged left edge that right-alignment produced for short keys.
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(infobox.indices, id: \.self) { index in
                    let item = infobox[index]
                    if let key = item.key, let value = item.value {
                        GridRow(alignment: .top) {
                            Text(key)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(value.displayText)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
    }
}
