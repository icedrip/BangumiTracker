import SwiftUI

/// Small "18+" badge shown on NSFW subject cards and detail views.
struct NSFWBadge: View {
    var body: some View {
        Text("18+")
            .font(.caption2.weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

/// Filters NSFW content from an array of Subjects when the preference is off.
/// Uses `UserDefaults.standard.bool(forKey: "pref.nsfwVisible")` directly so it
/// works from any context without an injected preference object.
extension Sequence where Element == Subject {
    var withoutNSFW: [Subject] {
        guard !UserDefaults.standard.bool(forKey: "pref.nsfwVisible") else { return Array(self) }
        return filter { !$0.nsfw }
    }
}

extension Array where Element == Subject {
    var withoutNSFW: [Subject] {
        guard !UserDefaults.standard.bool(forKey: "pref.nsfwVisible") else { return self }
        return filter { !$0.nsfw }
    }
}
