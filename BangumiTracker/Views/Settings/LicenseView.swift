import SwiftUI

/// Open-source licenses screen (PRD 5.2.7 关于 → 开源许可). Lists the app's
/// one third-party SPM dependency (Kingfisher) with its license text, plus the
/// Apple frameworks and the Bangumi data source.
struct LicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kingfisher")
                        .font(.body.weight(.semibold))
                    Text("https://github.com/onevcat/Kingfisher")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("© Wei Wang (onevcat) — MIT License")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(Self.kingfisherLicense)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple 框架")
                        .font(.body.weight(.semibold))
                    Text("SwiftUI · SwiftData · Foundation · UIKit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("随 iOS SDK 提供，受 Apple 软件许可协议约束。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Bangumi API")
                        .font(.body.weight(.semibold))
                    Text("https://bangumi.github.io/api")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("数据来源为 Bangumi (bgm.tv)，本应用为第三方客户端，不附属于 Bangumi。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let kingfisherLicense = """
    MIT License

    Copyright (c) 2019 Wei Wang

    Permission is hereby granted, free of charge, to any person obtaining a copy \
    of this software and associated documentation files (the "Software"), to deal \
    in the Software without restriction, including without limitation the rights \
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
    copies of the Software, and to permit persons to whom the Software is \
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in \
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN \
    THE SOFTWARE.
    """
}
