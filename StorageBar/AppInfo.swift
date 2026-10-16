import AppKit

/// Static facts shown in the About panel and used for links.
enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/ahsansabir30/StorageBar")!
    static let licence = "MIT Licence"
    static let summary = "Shows the free space on your startup disk in the menu bar."

    /// The standard About panel: name and version come from the bundle; credits carry the rest.
    @MainActor
    static func showAbout() {
        let credits = NSMutableAttributedString(
            string: "\(summary)\n\(licence) · ",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        credits.append(NSAttributedString(
            string: "GitHub",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .link: repositoryURL,
            ]
        ))
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centred, range: NSRange(location: 0, length: credits.length))

        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
