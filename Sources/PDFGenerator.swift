import UIKit

/// Renders a polished, personalized life-insurance coverage proposal as a PDF.
/// This is the real document Jordan "sends over" after a call.
enum PDFGenerator {
    // US Letter.
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 54

    // Brand palette (matches the app).
    private static let navy = UIColor(red: 0.05, green: 0.07, blue: 0.16, alpha: 1)
    private static let cyan = UIColor(red: 0.13, green: 0.72, blue: 0.92, alpha: 1)
    private static let blue = UIColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1)
    private static let ink  = UIColor(red: 0.12, green: 0.13, blue: 0.18, alpha: 1)
    private static let gray = UIColor(red: 0.42, green: 0.45, blue: 0.52, alpha: 1)

    /// Build the proposal PDF for a lead. Returns PDF file data.
    static func coverageProposal(for lead: Lead) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext
            var y = drawHeader(cg)
            y = drawPreparedFor(cg, lead: lead, startY: y + 28)
            y = drawProposalCard(cg, lead: lead, startY: y + 22)
            y = drawSituation(cg, lead: lead, startY: y + 26)
            y = drawNextSteps(cg, lead: lead, startY: y + 24)
            drawFooter(cg)
        }
    }

    // MARK: - Sections

    private static func drawHeader(_ cg: CGContext) -> CGFloat {
        let bandH: CGFloat = 132
        // Gradient band.
        let colors = [navy.cgColor, blue.cgColor] as CFArray
        let space = CGColorSpaceCreateDeviceRGB()
        if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            cg.saveGState()
            cg.addRect(CGRect(x: 0, y: 0, width: pageWidth, height: bandH))
            cg.clip()
            cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0),
                                  end: CGPoint(x: pageWidth, y: bandH), options: [])
            cg.restoreGState()
        }
        // Shield glyph.
        if let shield = UIImage(systemName: "shield.lefthalf.filled")?
            .withTintColor(.white, renderingMode: .alwaysOriginal) {
            shield.draw(in: CGRect(x: margin, y: 40, width: 30, height: 34))
        }
        draw("LifeCall", at: CGPoint(x: margin + 40, y: 44),
             font: .systemFont(ofSize: 26, weight: .bold), color: .white)
        draw("PERSONALIZED COVERAGE PROPOSAL", at: CGPoint(x: margin + 40, y: 78),
             font: .systemFont(ofSize: 11, weight: .semibold), color: UIColor.white.withAlphaComponent(0.7))
        // Date, right-aligned.
        let df = DateFormatter(); df.dateStyle = .long
        drawRight(df.string(from: Date()), rightX: pageWidth - margin, y: 48,
                  font: .systemFont(ofSize: 11, weight: .medium), color: UIColor.white.withAlphaComponent(0.85))
        return bandH
    }

    private static func drawPreparedFor(_ cg: CGContext, lead: Lead, startY: CGFloat) -> CGFloat {
        draw("PREPARED FOR", at: CGPoint(x: margin, y: startY),
             font: .systemFont(ofSize: 10, weight: .semibold), color: cyan)
        draw(lead.name ?? "Valued Client", at: CGPoint(x: margin, y: startY + 16),
             font: .systemFont(ofSize: 22, weight: .bold), color: ink)
        var sub: [String] = []
        if let a = lead.age { sub.append("Age \(a)") }
        if let e = lead.email, !e.isEmpty { sub.append(e) }
        if let p = lead.phone, !p.isEmpty { sub.append(p) }
        if !sub.isEmpty {
            draw(sub.joined(separator: "  ·  "), at: CGPoint(x: margin, y: startY + 46),
                 font: .systemFont(ofSize: 12, weight: .regular), color: gray)
            return startY + 64
        }
        return startY + 48
    }

    private static func drawProposalCard(_ cg: CGContext, lead: Lead, startY: CGFloat) -> CGFloat {
        let cardX = margin, cardW = pageWidth - margin * 2
        let rows = proposalRows(lead)
        let rowH: CGFloat = 34
        let headH: CGFloat = 38
        let cardH = headH + CGFloat(rows.count) * rowH + 12

        // Card background.
        let card = CGRect(x: cardX, y: startY, width: cardW, height: cardH)
        let path = UIBezierPath(roundedRect: card, cornerRadius: 14)
        UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1).setFill()
        path.fill()

        // Card header strip.
        let head = CGRect(x: cardX, y: startY, width: cardW, height: headH)
        let headPath = UIBezierPath(roundedRect: head, byRoundingCorners: [.topLeft, .topRight],
                                    cornerRadii: CGSize(width: 14, height: 14))
        navy.setFill(); headPath.fill()
        draw("YOUR RECOMMENDED COVERAGE", at: CGPoint(x: cardX + 18, y: startY + 13),
             font: .systemFont(ofSize: 11, weight: .bold), color: .white)

        var ry = startY + headH + 6
        for (label, value) in rows {
            draw(label, at: CGPoint(x: cardX + 18, y: ry + 9),
                 font: .systemFont(ofSize: 12, weight: .regular), color: gray)
            drawRight(value, rightX: cardX + cardW - 18, y: ry + 7,
                      font: .systemFont(ofSize: 14, weight: .semibold), color: ink)
            ry += rowH
            // Divider.
            cg.setStrokeColor(UIColor(white: 0.9, alpha: 1).cgColor)
            cg.setLineWidth(0.5)
            cg.move(to: CGPoint(x: cardX + 18, y: ry)); cg.addLine(to: CGPoint(x: cardX + cardW - 18, y: ry))
            cg.strokePath()
        }
        return startY + cardH
    }

    private static func drawSituation(_ cg: CGContext, lead: Lead, startY: CGFloat) -> CGFloat {
        guard let summary = lead.summary, !summary.isEmpty else { return startY }
        draw("YOUR SITUATION", at: CGPoint(x: margin, y: startY),
             font: .systemFont(ofSize: 11, weight: .bold), color: cyan)
        let box = CGRect(x: margin, y: startY + 18, width: pageWidth - margin * 2, height: 200)
        let h = drawWrapped(summary, in: box,
                            font: .systemFont(ofSize: 12.5, weight: .regular), color: ink, lineSpacing: 4)
        return startY + 18 + h
    }

    private static func drawNextSteps(_ cg: CGContext, lead: Lead, startY: CGFloat) -> CGFloat {
        draw("NEXT STEPS", at: CGPoint(x: margin, y: startY),
             font: .systemFont(ofSize: 11, weight: .bold), color: cyan)
        let steps = nextSteps(for: lead)
        var y = startY + 22
        for (i, step) in steps.enumerated() {
            // Number chip.
            let chip = CGRect(x: margin, y: y, width: 20, height: 20)
            blue.setFill(); UIBezierPath(ovalIn: chip).fill()
            drawCentered("\(i + 1)", in: chip, font: .systemFont(ofSize: 11, weight: .bold), color: .white)
            let box = CGRect(x: margin + 32, y: y - 1, width: pageWidth - margin * 2 - 32, height: 60)
            let h = drawWrapped(step, in: box, font: .systemFont(ofSize: 12.5, weight: .regular),
                                color: ink, lineSpacing: 3)
            y += max(28, h + 10)
        }
        return y
    }

    private static func drawFooter(_ cg: CGContext) {
        let y = pageHeight - 64
        cg.setStrokeColor(UIColor(white: 0.88, alpha: 1).cgColor); cg.setLineWidth(0.5)
        cg.move(to: CGPoint(x: margin, y: y)); cg.addLine(to: CGPoint(x: pageWidth - margin, y: y)); cg.strokePath()
        let disclaimer = "This proposal is an illustration prepared by your LifeCall broker and is not a contract or guarantee of coverage. Final premiums are subject to carrier underwriting approval. Questions? Reply to this email and Jordan will follow up."
        drawWrapped(disclaimer, in: CGRect(x: margin, y: y + 8, width: pageWidth - margin * 2, height: 48),
                    font: .systemFont(ofSize: 8.5, weight: .regular), color: gray, lineSpacing: 2)
    }

    // MARK: - Content

    private static func proposalRows(_ lead: Lead) -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Carrier", carrier(for: lead)))
        rows.append(("Product", productName(lead.coverageType)))
        if let amt = lead.coverageAmount, !amt.isEmpty { rows.append(("Coverage amount", amt)) }
        if let bud = lead.monthlyBudget, !bud.isEmpty { rows.append(("Estimated premium", bud)) }
        rows.append(("Underwriting", "Simplified issue — no medical exam")) // demo-friendly default
        return rows
    }

    /// Pull a named carrier out of the fact-find if Jordan quoted one, else a sensible default.
    private static func carrier(for lead: Lead) -> String {
        // Match against keywords, mapping to the carrier's proper display name.
        let known: [(needle: String, name: String)] = [
            ("banner", "Banner Life"), ("legal & general", "Banner Life"),
            ("protective", "Protective"), ("pacific life", "Pacific Life"),
            ("northwestern", "Northwestern Mutual"), ("massmutual", "MassMutual"),
            ("mass mutual", "MassMutual"), ("guardian", "Guardian"),
            ("new york life", "New York Life"), ("nationwide", "Nationwide"),
            ("allianz", "Allianz"), ("lincoln", "Lincoln Financial"),
            ("mutual of omaha", "Mutual of Omaha"), ("foresters", "Foresters"),
            ("aig", "AIG"), ("corebridge", "AIG"),
        ]
        let rec = (lead.factFind?.recommendedProduct ?? "").lowercased()
        if let hit = known.first(where: { rec.contains($0.needle) }) {
            return hit.name
        }
        // Default by product.
        switch lead.coverageType?.lowercased() {
        case "whole":          return "Northwestern Mutual"
        case "iul", "universal": return "Pacific Life"
        case "final_expense":  return "Mutual of Omaha"
        default:               return "Banner Life"
        }
    }

    private static func productName(_ type: String?) -> String {
        switch type?.lowercased() {
        case "term":           return "Term Life"
        case "whole":          return "Whole Life"
        case "universal":      return "Universal Life (UL)"
        case "iul":            return "Indexed Universal Life (IUL)"
        case "final_expense":  return "Final Expense"
        default:               return "Term Life"
        }
    }

    private static func nextSteps(for lead: Lead) -> [String] {
        switch lead.outcome {
        case "booked", "qualified":
            return [
                "Review the coverage above — it reflects what we discussed.",
                "Open the secure link to e-sign and set up payment.",
                "Jordan will call to confirm everything's in order."
            ]
        default:
            return [
                "Look over this proposal and the guides in your email.",
                "Jot down any questions — nothing is locked in yet.",
                "Jordan will follow up at the time you set."
            ]
        }
    }

    // MARK: - Drawing helpers

    private static func draw(_ text: String, at p: CGPoint, font: UIFont, color: UIColor) {
        text.draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
    }

    private static func drawRight(_ text: String, rightX: CGFloat, y: CGFloat, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        text.draw(at: CGPoint(x: rightX - size.width, y: y), withAttributes: attrs)
    }

    private static func drawCentered(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }

    @discardableResult
    private static func drawWrapped(_ text: String, in rect: CGRect, font: UIFont,
                                    color: UIColor, lineSpacing: CGFloat) -> CGFloat {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let bounds = attr.boundingRect(with: CGSize(width: rect.width, height: rect.height),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        attr.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(bounds.height)
    }
}
