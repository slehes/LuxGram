import Foundation
import Postbox
import TelegramCore

struct ChatSearchState: Equatable {
    let query: String
    let location: SearchMessagesLocation
    // MARK: - LuxGram
    let onlyDeleted: Bool
    // MARK: - End LuxGram
    let loadMoreState: SearchMessagesState?
}
