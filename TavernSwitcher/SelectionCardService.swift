import UIKit

@MainActor
enum SelectionCardService {
    static func makeCard(text rawText: String, character rawCharacter: String?) -> UIImage {
        let text = rawText
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCharacter = rawCharacter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let character = cleanedCharacter.isEmpty ? "AI Message" : cleanedCharacter

        let width: CGFloat = 1080
        let maxTextHeight: CGFloat = 1120
        let horizontalPadding: CGFloat = 86
        let topPadding: CGFloat = 96
        let bottomPadding: CGFloat = 94
        let titleHeight: CGFloat = 88

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 12
        paragraph.paragraphSpacing = 16
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail

        let textFont = UIFont.systemFont(ofSize: 45, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.94),
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let bounded = CGSize(width: width - horizontalPadding * 2, height: maxTextHeight)
        let measured = attributed.boundingRect(
            with: bounded,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral
        let height = min(1620, max(760, topPadding + titleHeight + measured.height + bottomPadding))

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)

            let colors = [
                UIColor(red: 0.055, green: 0.082, blue: 0.145, alpha: 1).cgColor,
                UIColor(red: 0.09, green: 0.12, blue: 0.22, alpha: 1).cgColor,
                UIColor(red: 0.16, green: 0.09, blue: 0.24, alpha: 1).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0, 0.56, 1]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations)!
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: width, y: height), options: [])

            cg.setFillColor(UIColor.white.withAlphaComponent(0.08).cgColor)
            cg.fillEllipse(in: CGRect(x: -160, y: -110, width: 460, height: 460))
            cg.setFillColor(UIColor(red: 1, green: 0.78, blue: 0.28, alpha: 0.12).cgColor)
            cg.fillEllipse(in: CGRect(x: width - 260, y: height - 320, width: 420, height: 420))

            let cardRect = bounds.insetBy(dx: 42, dy: 42)
            let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 54)
            UIColor.white.withAlphaComponent(0.10).setFill()
            path.fill()
            UIColor.white.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 2
            path.stroke()

            let badgeRect = CGRect(x: horizontalPadding, y: topPadding - 10, width: 74, height: 74)
            let badge = UIBezierPath(roundedRect: badgeRect, cornerRadius: 22)
            UIColor(red: 1, green: 0.80, blue: 0.25, alpha: 0.95).setFill()
            badge.fill()
            let spark = NSAttributedString(string: "✦", attributes: [
                .font: UIFont.systemFont(ofSize: 38, weight: .black),
                .foregroundColor: UIColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1)
            ])
            spark.draw(in: badgeRect.offsetBy(dx: 0, dy: 9))

            let title = NSAttributedString(string: character, attributes: [
                .font: UIFont.systemFont(ofSize: 38, weight: .bold),
                .foregroundColor: UIColor.white
            ])
            title.draw(in: CGRect(x: horizontalPadding + 94, y: topPadding - 2, width: width - horizontalPadding * 2 - 94, height: 44))

            let sub = NSAttributedString(string: "云洞酒馆 · 选中生成卡片", attributes: [
                .font: UIFont.systemFont(ofSize: 25, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.58)
            ])
            sub.draw(in: CGRect(x: horizontalPadding + 94, y: topPadding + 43, width: width - horizontalPadding * 2 - 94, height: 36))

            let quote = NSAttributedString(string: "“", attributes: [
                .font: UIFont.systemFont(ofSize: 110, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.18)
            ])
            quote.draw(in: CGRect(x: horizontalPadding - 12, y: topPadding + 106, width: 100, height: 120))

            attributed.draw(with: CGRect(
                x: horizontalPadding,
                y: topPadding + titleHeight + 68,
                width: width - horizontalPadding * 2,
                height: maxTextHeight
            ), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

            let footer = NSAttributedString(string: "Generated by TavernSwitcher", attributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.46)
            ])
            footer.draw(in: CGRect(x: horizontalPadding, y: height - 86, width: width - horizontalPadding * 2, height: 34))
        }
    }
}

