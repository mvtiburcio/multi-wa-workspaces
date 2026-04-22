import AppKit
import SwiftUI

struct WorkspaceAvatarCropState: Equatable {
  var zoom: CGFloat = 1
  var offset: CGSize = .zero
}

enum WorkspaceAvatarCropError: LocalizedError {
  case cannotReadImage
  case cannotEncodePNG

  var errorDescription: String? {
    switch self {
    case .cannotReadImage:
      "Não foi possível processar a imagem selecionada."
    case .cannotEncodePNG:
      "Não foi possível exportar o recorte em PNG."
    }
  }
}

enum WorkspaceAvatarCropRenderer {
  static let cropCanvasSize: CGFloat = 280
  static let outputPixels = 512

  static func sourcePixelSize(for image: NSImage) -> CGSize {
    if let cgImage = cgImage(from: image) {
      return CGSize(width: cgImage.width, height: cgImage.height)
    }
    return image.size
  }

  static func clampedState(
    for sourceSize: CGSize,
    state: WorkspaceAvatarCropState,
    cropSize: CGFloat = cropCanvasSize
  ) -> WorkspaceAvatarCropState {
    guard sourceSize.width > 0, sourceSize.height > 0 else {
      return WorkspaceAvatarCropState(zoom: 1, offset: .zero)
    }

    let zoom = min(max(state.zoom, 1.0), 4.0)
    let display = displayedSize(sourceSize: sourceSize, zoom: zoom, cropSize: cropSize)
    let maxX = max(0, (display.width - cropSize) / 2)
    let maxY = max(0, (display.height - cropSize) / 2)

    let clampedOffset = CGSize(
      width: min(max(state.offset.width, -maxX), maxX),
      height: min(max(state.offset.height, -maxY), maxY)
    )

    return WorkspaceAvatarCropState(zoom: zoom, offset: clampedOffset)
  }

  static func displayedSize(sourceSize: CGSize, zoom: CGFloat, cropSize: CGFloat = cropCanvasSize) -> CGSize {
    let baseScale = max(cropSize / sourceSize.width, cropSize / sourceSize.height)
    return CGSize(
      width: sourceSize.width * baseScale * zoom,
      height: sourceSize.height * baseScale * zoom
    )
  }

  static func renderPNG(
    from sourceImage: NSImage,
    state: WorkspaceAvatarCropState,
    cropSize: CGFloat = cropCanvasSize,
    outputPixels: Int = outputPixels
  ) throws -> Data {
    guard let cgImage = cgImage(from: sourceImage) else {
      throw WorkspaceAvatarCropError.cannotReadImage
    }

    let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
    let clamped = clampedState(for: sourceSize, state: state, cropSize: cropSize)
    let display = displayedSize(sourceSize: sourceSize, zoom: clamped.zoom, cropSize: cropSize)

    let outputSize = CGFloat(outputPixels)
    let factor = outputSize / cropSize

    let drawWidth = display.width * factor
    let drawHeight = display.height * factor

    let topLeftX = ((cropSize - display.width) / 2 + clamped.offset.width) * factor
    let topLeftY = ((cropSize - display.height) / 2 + clamped.offset.height) * factor

    guard
      let context = CGContext(
        data: nil,
        width: outputPixels,
        height: outputPixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw WorkspaceAvatarCropError.cannotEncodePNG
    }

    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: outputSize, height: outputSize))

    context.addEllipse(in: CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
    context.clip()

    let drawRect = CGRect(
      x: topLeftX,
      y: outputSize - topLeftY - drawHeight,
      width: drawWidth,
      height: drawHeight
    )
    context.draw(cgImage, in: drawRect)

    guard let outputImage = context.makeImage() else {
      throw WorkspaceAvatarCropError.cannotEncodePNG
    }

    let bitmap = NSBitmapImageRep(cgImage: outputImage)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
      throw WorkspaceAvatarCropError.cannotEncodePNG
    }

    return pngData
  }

  private static func cgImage(from image: NSImage) -> CGImage? {
    if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
      return cg
    }

    guard
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let cg = rep.cgImage
    else {
      return nil
    }
    return cg
  }
}

struct WorkspaceAvatarCropSheet: View {
  let workspaceName: String
  let sourceImage: NSImage
  let onCancel: () -> Void
  let onConfirm: (WorkspaceAvatarCropState) -> Void

  @State private var cropState = WorkspaceAvatarCropState()
  @State private var dragBaseOffset: CGSize = .zero

  private let cropSize = WorkspaceAvatarCropRenderer.cropCanvasSize

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Recortar foto do workspace")
        .font(.title3.bold())

      Text(workspaceName)
        .font(.caption)
        .foregroundStyle(.secondary)

      cropPreview

      HStack(spacing: 12) {
        Text("Zoom")
          .font(.caption)
          .foregroundStyle(.secondary)

        Slider(value: zoomBinding, in: 1...4, step: 0.01)

        Text(String(format: "%.0f%%", cropState.zoom * 100))
          .font(.caption.monospacedDigit())
          .frame(width: 54, alignment: .trailing)
      }

      HStack {
        Button("Centralizar") {
          cropState.offset = .zero
          dragBaseOffset = .zero
        }

        Spacer()

        Button("Cancelar") {
          onCancel()
        }

        Button("Salvar") {
          onConfirm(clampedState)
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 440)
  }

  private var sourceSize: CGSize {
    WorkspaceAvatarCropRenderer.sourcePixelSize(for: sourceImage)
  }

  private var clampedState: WorkspaceAvatarCropState {
    WorkspaceAvatarCropRenderer.clampedState(for: sourceSize, state: cropState, cropSize: cropSize)
  }

  private var displaySize: CGSize {
    WorkspaceAvatarCropRenderer.displayedSize(sourceSize: sourceSize, zoom: clampedState.zoom, cropSize: cropSize)
  }

  private var zoomBinding: Binding<Double> {
    Binding(
      get: { Double(cropState.zoom) },
      set: { newValue in
        cropState.zoom = CGFloat(newValue)
        let clamped = clampedState
        cropState = clamped
        dragBaseOffset = clamped.offset
      }
    )
  }

  private var cropPreview: some View {
    ZStack {
      Circle()
        .fill(.black.opacity(0.1))
        .frame(width: cropSize, height: cropSize)

      Image(nsImage: sourceImage)
        .resizable()
        .interpolation(.high)
        .frame(width: displaySize.width, height: displaySize.height)
        .offset(clampedState.offset)
        .clipShape(Circle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              cropState.offset = CGSize(
                width: dragBaseOffset.width + value.translation.width,
                height: dragBaseOffset.height + value.translation.height
              )
              cropState = clampedState
            }
            .onEnded { _ in
              cropState = clampedState
              dragBaseOffset = cropState.offset
            }
        )

      Circle()
        .stroke(.white.opacity(0.7), lineWidth: 2)
        .frame(width: cropSize, height: cropSize)
    }
    .frame(maxWidth: .infinity)
    .frame(height: cropSize + 20)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
  }
}
