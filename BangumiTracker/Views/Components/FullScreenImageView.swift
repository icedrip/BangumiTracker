import SwiftUI
import Kingfisher

struct FullScreenImageView: View {
    let urlString: String?
    let title: String?
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var anchor: UnitPoint = .center
    @GestureState private var magnifyState: CGFloat = 1.0
    @GestureState private var dragActive: CGSize = .zero
    @State private var dragTotal: CGSize = .zero
    @State private var isDismissing = false
    /// The image's displayed (aspect-fit) frame at scale 1, captured via the
    /// background `GeometryReader`. The drag clamp uses this — not the screen
    /// size — to compute the real per-axis overflow, because an aspect-fit
    /// portrait poster doesn't fill a tall screen's height, so only the actual
    /// image overflow is pannable on that axis.
    @State private var imageSize: CGSize = .zero

    private var currentScale: CGFloat {
        isDismissing ? 1.0 : min(max(scale * magnifyState, 1.0), 5.0)
    }

    private var currentOffset: CGSize {
        isDismissing ? .zero : (scale > 1.0 ? CGSize(width: dragTotal.width + dragActive.width,
                                                       height: dragTotal.height + dragActive.height) : .zero)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let urlString, let url = URL(string: urlString) {
                KFImage(url)
                    .placeholder {
                        ProgressView()
                            .tint(.white)
                    }
                    .cacheOriginalImage()
                    .fade(duration: 0.2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    // Center in the full screen (not the safe area) so the
                    // image is screen-centered — the drag clamp assumes a
                    // centered image, and a safe-area-centered portrait poster
                    // sits ~14pt below screen center, which left a thin black
                    // sliver at the top after a max downward drag. The status
                    // bar is hidden and the close-button overlay keeps its own
                    // safe-area inset, so this only affects the image.
                    .ignoresSafeArea()
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { imageSize = geo.size }
                                .onChange(of: geo.size) { _, newSize in imageSize = newSize }
                        }
                    )
                    .scaleEffect(currentScale, anchor: anchor)
                    .offset(currentOffset)
                    .gesture(isDismissing ? nil : pinchGesture)
                    .simultaneousGesture(isDismissing ? nil : dragGesture)
                    .accessibilityLabel(title.map { "\($0) 封面大图" } ?? "封面大图")
                    .accessibilityHint("双击缩放，单击关闭")
                    .onTapGesture {
                        guard !isDismissing else { return }
                        if scale > 1.0 {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scale = 1.0
                                dragTotal = .zero
                            }
                        } else {
                            dismiss()
                        }
                    }
                    .onTapGesture(count: 2) {
                        guard !isDismissing else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if scale > 1.0 {
                                scale = 1.0
                                dragTotal = .zero
                            } else {
                                scale = 2.5
                                anchor = .center
                            }
                        }
                    }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.5))
            }

            VStack {
                HStack {
                    if let title {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .accessibilityLabel("关闭")
                }
                .padding(.horizontal, .horizontalPadding)
                .padding(.top, 12)
                Spacer()
            }
        }
        .statusBarHidden(true)
    }

    private func dismiss() {
        guard !isDismissing else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isDismissing = true
        } completion: {
            onDismiss()
        }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                anchor = value.startAnchor
            }
            .updating($magnifyState) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                let newScale = scale * value.magnification
                scale = min(max(newScale, 1.0), 5.0)
                anchor = value.startAnchor
                if scale <= 1.0 {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scale = 1.0
                        dragTotal = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragActive) { value, state, _ in
                if scale > 1.0 {
                    state = value.translation
                }
            }
            .onEnded { value in
                guard scale > 1.0 else { return }
                // Clamp so the image can't be dragged past its own edges — a
                // gap would reveal the black background where there's no image
                // to show. The scaled image overflows the screen by
                // (displayedSize × scale − screenSize) / 2 per axis; bound the
                // cumulative offset to that. Using the screen size alone
                // (screenDimension × (scale−1) / 2) over-permits on the axis
                // the aspect-fit image doesn't fill: a portrait poster on a
                // tall screen under-fills the height, so the screen-based
                // formula allowed ~12× the real vertical overflow and left a
                // large black bar after a drag.
                let container = UIScreen.main.bounds.size
                let maxDX = max(0, (imageSize.width * scale - container.width) / 2)
                let maxDY = max(0, (imageSize.height * scale - container.height) / 2)
                let clampedX = min(max(dragTotal.width + value.translation.width, -maxDX), maxDX)
                let clampedY = min(max(dragTotal.height + value.translation.height, -maxDY), maxDY)
                dragTotal = CGSize(width: clampedX, height: clampedY)
            }
    }
}
