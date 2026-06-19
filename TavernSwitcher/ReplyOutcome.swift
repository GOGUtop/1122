import Foundation

enum ReplyOutcome: String, Codable, CaseIterable, Identifiable {
    case complete
    case truncated
    case empty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .complete: return "回复完整完成"
        case .truncated: return "回复被截断"
        case .empty: return "本次为空回"
        }
    }

    var notificationBody: String {
        switch self {
        case .complete: return "角色已经完整回复完毕。"
        case .truncated: return "回复达到长度限制或被提前停止，可以继续生成。"
        case .empty: return "本次生成没有得到有效正文。"
        }
    }
}
