import SwiftUI

// MARK: - Spacing

extension CGFloat {
    /// Standard horizontal padding for content (16pt).
    static let horizontalPadding: CGFloat = 16
    /// Standard vertical padding between sections (12pt).
    static let sectionSpacing: CGFloat = 12
    /// Tight vertical padding (8pt).
    static let tightSpacing: CGFloat = 8
    /// Extra-tight vertical padding (4pt).
    static let extraTightSpacing: CGFloat = 4
}

// MARK: - Corner Radius

extension CGFloat {
    /// Standard card corner radius (10pt).
    static let cardRadius: CGFloat = 10
    /// Small corner radius (6pt).
    static let smallRadius: CGFloat = 6
}

// MARK: - Image Sizing

extension CGFloat {
    /// Hero cover image height (200pt).
    static let heroHeight: CGFloat = 200
    /// Subject card poster height (140pt).
    static let posterHeight: CGFloat = 140
    /// Small avatar / icon size (40pt).
    static let iconSize: CGFloat = 40
}

// MARK: - Font

extension UIFont.TextStyle {
    /// Maps design-token font sizes to Dynamic Type text styles.
    /// See P1-02 for full Dynamic Type adoption.
    static let caption: UIFont.TextStyle = .caption1
    static let body: UIFont.TextStyle = .body
    static let headline: UIFont.TextStyle = .headline
}
