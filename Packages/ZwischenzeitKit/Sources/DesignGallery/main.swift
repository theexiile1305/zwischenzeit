// Renders DesignGalleryView to PNG (light and dark) so the design system can be
// checked without Xcode or a simulator.
//
//     swift run --package-path Packages/ZwischenzeitKit DesignGallery <output-dir>

import AppKit
import DesignSystem
import SwiftUI

@MainActor
func render(_ scheme: ColorScheme, to url: URL) throws {
    let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
    var image: CGImage?
    appearance.performAsCurrentDrawingAppearance {
        let renderer = ImageRenderer(content: DesignGalleryView().environment(\.colorScheme, scheme))
        renderer.scale = 2
        image = renderer.cgImage
    }
    guard let image else { throw CocoaError(.fileWriteUnknown) }
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try MainActor.assumeIsolated {
    NSApplication.shared.appearance = NSAppearance(named: .aqua)
    try render(.light, to: out.appendingPathComponent("gallery-light.png"))
    NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    try render(.dark, to: out.appendingPathComponent("gallery-dark.png"))
}
