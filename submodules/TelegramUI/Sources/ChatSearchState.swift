import Foundation
import Postbox
import TelegramCore

struct ChatSearchState: Equatable {
    let query: String
    let location: SearchMessagesLocation
    let onlyDeleted: Bool
    let loadMoreState: SearchMessagesState?
}
