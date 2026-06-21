import UIKit

@MainActor
enum SelectionCardService {
    static func makeCard(text rawText: String, character rawCharacter: String?, theme rawTheme: String? = nil) -> UIImage {
        let text = rawText
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCharacter = rawCharacter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let character = cleanedCharacter.isEmpty ? "AI Message" : cleanedCharacter
        let theme = CardTheme.resolve(rawTheme)

        let width: CGFloat = 1080
        let maxTextHeight: CGFloat = 1260
        let horizontalPadding: CGFloat = 86
        let topPadding: CGFloat = 94
        let bottomPadding: CGFloat = 96
        let headerHeight: CGFloat = 108

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 13
        paragraph.paragraphSpacing = 18
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail

        let textFont = UIFont.systemFont(ofSize: theme.light ? 43 : 45, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: theme.text.withAlphaComponent(theme.light ? 0.88 : 0.94),
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let bounded = CGSize(width: width - horizontalPadding * 2, height: maxTextHeight)
        let measured = attributed.boundingRect(
            with: bounded,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral
        let height = min(1760, max(790, topPadding + headerHeight + measured.height + bottomPadding + 58))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)

            drawBackground(theme: theme, in: bounds, context: cg)
            drawDecor(theme: theme, width: width, height: height, context: cg)

            let cardRect = bounds.insetBy(dx: 42, dy: 42)
            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 58)
            theme.surface.setFill()
            cardPath.fill()
            theme.stroke.setStroke()
            cardPath.lineWidth = 2.2
            cardPath.stroke()

            let badgeRect = CGRect(x: horizontalPadding, y: topPadding - 7, width: 78, height: 78)
            let badge = UIBezierPath(roundedRect: badgeRect, cornerRadius: 24)
            theme.accent.setFill()
            badge.fill()
            let icon = NSAttributedString(string: theme.icon, attributes: [
                .font: UIFont.systemFont(ofSize: 36, weight: .black),
                .foregroundColor: theme.badgeText
            ])
            icon.draw(in: badgeRect.insetBy(dx: 0, dy: 17))

            let title = NSAttributedString(string: character, attributes: [
                .font: UIFont.systemFont(ofSize: 39, weight: .heavy),
                .foregroundColor: theme.text
            ])
            title.draw(in: CGRect(x: horizontalPadding + 98, y: topPadding - 2, width: width - horizontalPadding * 2 - 98, height: 48))

            let sub = NSAttributedString(string: "云洞酒馆 · \(theme.name)", attributes: [
                .font: UIFont.systemFont(ofSize: 25, weight: .semibold),
                .foregroundColor: theme.subtext
            ])
            sub.draw(in: CGRect(x: horizontalPadding + 98, y: topPadding + 48, width: width - horizontalPadding * 2 - 98, height: 36))

            let quote = NSAttributedString(string: "“", attributes: [
                .font: UIFont.systemFont(ofSize: 118, weight: .heavy),
                .foregroundColor: theme.text.withAlphaComponent(theme.light ? 0.10 : 0.16)
            ])
            quote.draw(in: CGRect(x: horizontalPadding - 12, y: topPadding + 120, width: 120, height: 120))

            attributed.draw(with: CGRect(
                x: horizontalPadding,
                y: topPadding + headerHeight + 64,
                width: width - horizontalPadding * 2,
                height: maxTextHeight
            ), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

            let tagRect = CGRect(x: horizontalPadding, y: height - 88, width: 260, height: 42)
            let tagPath = UIBezierPath(roundedRect: tagRect, cornerRadius: 21)
            theme.accent.withAlphaComponent(theme.light ? 0.18 : 0.22).setFill()
            tagPath.fill()
            let tag = NSAttributedString(string: "TavernSwitcher", attributes: [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: theme.text.withAlphaComponent(theme.light ? 0.62 : 0.72)
            ])
            tag.draw(in: tagRect.insetBy(dx: 18, dy: 8))

            let footer = NSAttributedString(string: theme.footer, attributes: [
                .font: UIFont.systemFont(ofSize: 23, weight: .medium),
                .foregroundColor: theme.subtext.withAlphaComponent(0.88)
            ])
            footer.draw(in: CGRect(x: horizontalPadding + 290, y: height - 82, width: width - horizontalPadding * 2 - 290, height: 34))
        }
    }

    private static func drawBackground(theme: CardTheme, in bounds: CGRect, context cg: CGContext) {
        let colors = theme.gradient.map { $0.cgColor } as CFArray
        let locations = theme.locations
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations)!
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.minX, y: bounds.minY),
            end: CGPoint(x: bounds.maxX, y: bounds.maxY),
            options: []
        )
    }

    private static func drawDecor(theme: CardTheme, width: CGFloat, height: CGFloat, context cg: CGContext) {
        cg.saveGState()
        cg.setFillColor(theme.accent.withAlphaComponent(theme.light ? 0.13 : 0.18).cgColor)
        cg.fillEllipse(in: CGRect(x: -170, y: -125, width: 510, height: 510))
        cg.setFillColor(theme.secondary.withAlphaComponent(theme.light ? 0.12 : 0.16).cgColor)
        cg.fillEllipse(in: CGRect(x: width - 300, y: height - 350, width: 500, height: 500))

        cg.setStrokeColor(theme.text.withAlphaComponent(theme.light ? 0.07 : 0.10).cgColor)
        cg.setLineWidth(2)
        for i in 0..<5 {
            let inset = CGFloat(i) * 42
            cg.strokeEllipse(in: CGRect(x: width - 420 + inset, y: 76 + inset, width: 360 - inset, height: 360 - inset))
        }

        let stars = [
            CGPoint(x: 128, y: 250), CGPoint(x: 910, y: 180), CGPoint(x: 820, y: height - 190),
            CGPoint(x: 220, y: height - 220), CGPoint(x: 955, y: height * 0.48)
        ]
        let sparkAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .black),
            .foregroundColor: theme.accent.withAlphaComponent(theme.light ? 0.45 : 0.62)
        ]
        for point in stars {
            NSAttributedString(string: "✦", attributes: sparkAttrs).draw(in: CGRect(x: point.x, y: point.y, width: 36, height: 36))
        }
        cg.restoreGState()
    }
}

private struct CardTheme {
    let id: String
    let name: String
    let icon: String
    let footer: String
    let gradient: [UIColor]
    let locations: [CGFloat]
    let surface: UIColor
    let stroke: UIColor
    let accent: UIColor
    let secondary: UIColor
    let text: UIColor
    let subtext: UIColor
    let badgeText: UIColor
    let light: Bool

    static func resolve(_ id: String?) -> CardTheme {
        let key = (id ?? "night").lowercased()
        return all.first(where: { $0.id == key }) ?? all[0]
    }

    static let all: [CardTheme] = [
        CardTheme(
            id: "night", name: "星夜玻璃", icon: "✦", footer: "Midnight glass card",
            gradient: [UIColor(hex: 0x07111F), UIColor(hex: 0x10294C), UIColor(hex: 0x25133B)], locations: [0, 0.56, 1],
            surface: UIColor.white.withAlphaComponent(0.10), stroke: UIColor.white.withAlphaComponent(0.20),
            accent: UIColor(hex: 0xFFD45A), secondary: UIColor(hex: 0x77B9FF),
            text: .white, subtext: UIColor.white.withAlphaComponent(0.58), badgeText: UIColor(hex: 0x14100B), light: false
        ),
        CardTheme(
            id: "cream", name: "奶油便签", icon: "♢", footer: "Soft note card",
            gradient: [UIColor(hex: 0xFFF2D8), UIColor(hex: 0xFCE7E8), UIColor(hex: 0xE9F2FF)], locations: [0, 0.52, 1],
            surface: UIColor.white.withAlphaComponent(0.54), stroke: UIColor.white.withAlphaComponent(0.72),
            accent: UIColor(hex: 0xFFB65C), secondary: UIColor(hex: 0xFF8CA8),
            text: UIColor(hex: 0x30243A), subtext: UIColor(hex: 0x30243A).withAlphaComponent(0.58), badgeText: UIColor(hex: 0x2B1C12), light: true
        ),
        CardTheme(
            id: "cyber", name: "赛博霓虹", icon: "◆", footer: "Cyber neon card",
            gradient: [UIColor(hex: 0x070A16), UIColor(hex: 0x161E52), UIColor(hex: 0x391052)], locations: [0, 0.58, 1],
            surface: UIColor(hex: 0x080B19).withAlphaComponent(0.56), stroke: UIColor(hex: 0x70E9FF).withAlphaComponent(0.30),
            accent: UIColor(hex: 0x70E9FF), secondary: UIColor(hex: 0xFF5AF7),
            text: UIColor(hex: 0xF5FCFF), subtext: UIColor(hex: 0xBFEFFF).withAlphaComponent(0.66), badgeText: UIColor(hex: 0x03131A), light: false
        ),
        CardTheme(
            id: "sakura", name: "樱粉胶片", icon: "✿", footer: "Sakura film card",
            gradient: [UIColor(hex: 0x3A1835), UIColor(hex: 0x9B315D), UIColor(hex: 0xFFC1D8)], locations: [0, 0.58, 1],
            surface: UIColor.white.withAlphaComponent(0.12), stroke: UIColor.white.withAlphaComponent(0.24),
            accent: UIColor(hex: 0xFFD1E1), secondary: UIColor(hex: 0xFF8AB8),
            text: .white, subtext: UIColor.white.withAlphaComponent(0.66), badgeText: UIColor(hex: 0x40152A), light: false
        ),
        CardTheme(
            id: "emerald", name: "墨绿诗页", icon: "❖", footer: "Emerald prose card",
            gradient: [UIColor(hex: 0x06231D), UIColor(hex: 0x0E4B3E), UIColor(hex: 0xC7A85B)], locations: [0, 0.66, 1],
            surface: UIColor.white.withAlphaComponent(0.10), stroke: UIColor.white.withAlphaComponent(0.18),
            accent: UIColor(hex: 0xD7BC6C), secondary: UIColor(hex: 0x74E3B1),
            text: UIColor(hex: 0xF7FFF8), subtext: UIColor(hex: 0xDDF2E5).withAlphaComponent(0.62), badgeText: UIColor(hex: 0x142016), light: false
        ),
        CardTheme(
            id: "aurora", name: "极光蓝紫", icon: "✧", footer: "Aurora dream card",
            gradient: [UIColor(hex: 0x10163A), UIColor(hex: 0x4057C8), UIColor(hex: 0xA870FF)], locations: [0, 0.58, 1],
            surface: UIColor.white.withAlphaComponent(0.11), stroke: UIColor.white.withAlphaComponent(0.22),
            accent: UIColor(hex: 0xB8F7FF), secondary: UIColor(hex: 0xD9B6FF),
            text: .white, subtext: UIColor.white.withAlphaComponent(0.64), badgeText: UIColor(hex: 0x111C36), light: false
        ),
        CardTheme(
            id: "ink", name: "黑金剧场", icon: "★", footer: "Black gold card",
            gradient: [UIColor(hex: 0x050505), UIColor(hex: 0x17120C), UIColor(hex: 0x3A2B13)], locations: [0, 0.55, 1],
            surface: UIColor.white.withAlphaComponent(0.08), stroke: UIColor(hex: 0xF0C15A).withAlphaComponent(0.22),
            accent: UIColor(hex: 0xF0C15A), secondary: UIColor(hex: 0xA27131),
            text: UIColor(hex: 0xFFF7E1), subtext: UIColor(hex: 0xFFF1C0).withAlphaComponent(0.56), badgeText: UIColor(hex: 0x120C04), light: false
        ),
        CardTheme(
            id: "minimal", name: "极简白卡", icon: "—", footer: "Minimal clean card",
            gradient: [UIColor(hex: 0xF9FAFF), UIColor(hex: 0xEEF3FF), UIColor(hex: 0xFFFFFF)], locations: [0, 0.64, 1],
            surface: UIColor.white.withAlphaComponent(0.68), stroke: UIColor(hex: 0xC8D3EA).withAlphaComponent(0.70),
            accent: UIColor(hex: 0x5D7CFF), secondary: UIColor(hex: 0x95B8FF),
            text: UIColor(hex: 0x192033), subtext: UIColor(hex: 0x192033).withAlphaComponent(0.54), badgeText: UIColor.white, light: true
        )
    ]
}

private extension UIColor {
    convenience init(hex: Int) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
