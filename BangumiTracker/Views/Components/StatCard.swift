import SwiftUI

struct StatCard: View {
    let label: String
    let count: Int
    let color: Color
    var showError: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 2) {
            Text(showError ? "--" : "\(count)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(showError ? .secondary : color)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .onTapGesture { onTap?() }
    }
}
