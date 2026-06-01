import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
#if canImport(SGLogging)
import SGLogging
#endif

// MARK: - Constants

private let messagesPerPage = 1000

// MARK: - Export Progress

public enum SGChatExportProgress {
    case preparing
    case exporting(current: Int, total: Int)
    case copyingMedia(current: Int, total: Int)
    case done(URL)
    case error(String)
}

// MARK: - Peer Display Name Helper

private func peerDisplayName(_ peer: Peer?) -> String {
    guard let peer = peer else { return "Unknown" }
    if let user = peer as? TelegramUser {
        let first = user.firstName ?? ""
        let last = user.lastName ?? ""
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? (user.username ?? "User") : name
    } else if let channel = peer as? TelegramChannel {
        return channel.title
    } else if let group = peer as? TelegramGroup {
        return group.title
    }
    return "Chat"
}

private func peerInitial(_ peer: Peer?) -> String {
    let name = peerDisplayName(peer)
    return String(name.prefix(1))
}

private func userpicColorIndex(_ peer: Peer?) -> Int {
    guard let peer = peer else { return 1 }
    let id = peer.id.id._internalGetInt64Value()
    return Int(abs(id) % 8) + 1
}

// MARK: - Chat Title Helper

private func chatTitle(peerId: PeerId, transaction: Transaction) -> String {
    if let peer = transaction.getPeer(peerId) {
        return peerDisplayName(peer)
    }
    return "Chat"
}

// MARK: - HTML Escaping

private func htmlEscape(_ text: String) -> String {
    return text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

// MARK: - Date Formatting

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "dd.MM.yyyy HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

private let dateSeparatorFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d MMMM yyyy"
    f.locale = Locale(identifier: "en_US")
    return f
}()

private let fileDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "dd-MM-yyyy_HH-mm-ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

private func timeZoneSuffix() -> String {
    let tz = TimeZone.current
    let seconds = tz.secondsFromGMT()
    let hours = seconds / 3600
    let minutes = abs(seconds % 3600) / 60
    return String(format: "UTC%+03d:%02d", hours, minutes)
}

// MARK: - Duration Formatting

private func formatDuration(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%02d:%02d", m, s)
}

// MARK: - Media Info

private struct MediaFileInfo {
    let sourceResourcePath: String?
    let exportSubdir: String
    let exportFileName: String
    let htmlBlock: String
}

private func mediaInfoForMessage(
    _ message: Message,
    mediaBox: MediaBox,
    messageDate: Date
) -> MediaFileInfo? {
    for media in message.media {
        if let image = media as? TelegramMediaImage {
            guard let largest = image.representations.last else { continue }
            let sourcePath = mediaBox.completedResourcePath(largest.resource, pathExtension: "jpg")
            let dateStr = fileDateFormatter.string(from: messageDate)
            let fileName = "photo_\(message.id.id)@\(dateStr).jpg"
            let thumbFileName = "photo_\(message.id.id)@\(dateStr)_thumb.jpg"
            let dims = largest.dimensions
            let w = min(Int(dims.width), 260)
            let h = Int(Double(dims.height) * Double(w) / max(Double(dims.width), 1))
            let html = """
             <div class="media_wrap clearfix">
              <a class="photo_wrap clearfix pull_left" href="photos/\(fileName)">
               <img class="photo" src="photos/\(thumbFileName)" style="width: \(w)px; height: \(h)px"/>
              </a>
             </div>
            """
            return MediaFileInfo(
                sourceResourcePath: sourcePath,
                exportSubdir: "photos",
                exportFileName: fileName,
                htmlBlock: html
            )
        }
        if let file = media as? TelegramMediaFile {
            let sourcePath = mediaBox.completedResourcePath(file.resource)
            let dateStr = fileDateFormatter.string(from: messageDate)

            if file.isVoice {
                let duration = Int(file.duration ?? 0)
                let fileName = "audio_\(message.id.id)@\(dateStr).ogg"
                let html = """
                 <div class="media_wrap clearfix">
                  <a class="media clearfix pull_left block_link media_voice_message" href="voice_messages/\(fileName)">
                   <div class="fill pull_left"></div>
                   <div class="body">
                    <div class="title bold">Voice message</div>
                    <div class="status details">\(formatDuration(duration))</div>
                   </div>
                  </a>
                 </div>
                """
                return MediaFileInfo(
                    sourceResourcePath: sourcePath,
                    exportSubdir: "voice_messages",
                    exportFileName: fileName,
                    htmlBlock: html
                )
            }

            if file.isInstantVideo {
                let duration = Int(file.duration ?? 0)
                let fileName = "round_\(message.id.id)@\(dateStr).mp4"
                let html = """
                 <div class="media_wrap clearfix">
                  <div class="video_file_wrap clearfix pull_left">
                   <a href="round_video_messages/\(fileName)">
                    <div class="video_play_bg"><div class="video_play"></div></div>
                   </a>
                   <div class="video_duration">\(formatDuration(duration))</div>
                  </div>
                 </div>
                """
                return MediaFileInfo(
                    sourceResourcePath: sourcePath,
                    exportSubdir: "round_video_messages",
                    exportFileName: fileName,
                    htmlBlock: html
                )
            }

            if file.isSticker {
                let fileName = "sticker_\(message.id.id)@\(dateStr).webp"
                let html = """
                 <div class="media_wrap clearfix">
                  <a href="stickers/\(fileName)">
                   <img class="sticker" src="stickers/\(fileName)" style="width: 256px; height: 256px"/>
                  </a>
                 </div>
                """
                return MediaFileInfo(
                    sourceResourcePath: sourcePath,
                    exportSubdir: "stickers",
                    exportFileName: fileName,
                    htmlBlock: html
                )
            }

            if file.isVideo {
                let duration = Int(file.duration ?? 0)
                let fileName = "video_\(message.id.id)@\(dateStr).mp4"
                let html = """
                 <div class="media_wrap clearfix">
                  <div class="video_file_wrap clearfix pull_left">
                   <a href="video_files/\(fileName)">
                    <div class="video_play_bg"><div class="video_play"></div></div>
                   </a>
                   <div class="video_duration">\(formatDuration(duration))</div>
                  </div>
                 </div>
                """
                return MediaFileInfo(
                    sourceResourcePath: sourcePath,
                    exportSubdir: "video_files",
                    exportFileName: fileName,
                    htmlBlock: html
                )
            }

            // Generic file
            let origName = file.fileName ?? "file_\(message.id.id)"
            let fileName = origName
            let fileSize = file.size ?? 0
            let sizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            let html = """
             <div class="media_wrap clearfix">
              <a class="media clearfix pull_left block_link media_file" href="files/\(htmlEscape(fileName))">
               <div class="fill pull_left"></div>
               <div class="body">
                <div class="title bold">\(htmlEscape(origName))</div>
                <div class="status details">\(sizeStr)</div>
               </div>
              </a>
             </div>
            """
            return MediaFileInfo(
                sourceResourcePath: sourcePath,
                exportSubdir: "files",
                exportFileName: fileName,
                htmlBlock: html
            )
        }
    }
    return nil
}

// MARK: - Reactions HTML

private func reactionsHTML(for message: Message) -> String {
    var reactionsAttr: ReactionsMessageAttribute?
    for attr in message.attributes {
        if let r = attr as? ReactionsMessageAttribute {
            reactionsAttr = r
            break
        }
    }
    guard let reactionsAttr = reactionsAttr, !reactionsAttr.reactions.isEmpty else {
        return ""
    }
    var html = "\n      <span class=\"reactions\">\n"
    for reaction in reactionsAttr.reactions {
        let isActive = reaction.chosenOrder != nil
        let activeClass = isActive ? " active" : ""
        var emojiStr = ""
        switch reaction.value {
        case let .builtin(emoji):
            emojiStr = emoji
        case .custom:
            emojiStr = "\u{2764}\u{FE0F}"
        case .stars:
            emojiStr = "\u{2B50}"
        }
        html += "       <span class=\"reaction\(activeClass)\">\n"
        html += "        <span class=\"emoji\">\(emojiStr)</span>\n"
        html += "        <span class=\"count\">\(reaction.count)</span>\n"
        html += "       </span>\n"
    }
    html += "      </span>\n"
    return html
}

// MARK: - Reply HTML

private func replyHTML(for message: Message) -> String {
    for attr in message.attributes {
        if let replyAttr = attr as? ReplyMessageAttribute {
            let replyId = replyAttr.messageId.id
            return """
                  <div class="reply_to details">
                   In reply to <a href="#go_to_message\(replyId)" onclick="return GoToMessage(\(replyId))">this message</a>
                  </div>
            """
        }
    }
    return ""
}

// MARK: - Forward Info HTML

private func forwardHTML(
    _ message: Message,
    mediaHTML: String,
    textHTML: String
) -> String {
    guard let fwd = message.forwardInfo else { return "" }
    let authorName = htmlEscape(peerDisplayName(fwd.author))
    let authorInitial = peerInitial(fwd.author)
    let authorColor = userpicColorIndex(fwd.author)
    let fwdDate = Date(timeIntervalSince1970: Double(fwd.date))
    let fwdDateStr = dateFormatter.string(from: fwdDate)

    var body = ""
    body += """
          <div class="pull_left forwarded userpic_wrap">
           <div class="userpic userpic\(authorColor)" style="width: 42px; height: 42px">
            <div class="initials" style="line-height: 42px">\(htmlEscape(authorInitial))</div>
           </div>
          </div>
          <div class="forwarded body">
           <div class="from_name">\(authorName) <span class="date details" title="\(fwdDateStr)"> \(fwdDateStr)</span></div>
    """
    if !mediaHTML.isEmpty {
        body += mediaHTML + "\n"
    }
    if !textHTML.isEmpty {
        body += "       <div class=\"text\">\(textHTML)</div>\n"
    }
    body += "      </div>\n"
    return body
}

// MARK: - Message Text Processing

private func processMessageText(_ text: String) -> String {
    guard !text.isEmpty else { return "" }

    // Escape HTML and convert newlines
    var result = htmlEscape(text)
    result = result.replacingOccurrences(of: "\n", with: "<br>")

    // Basic URL detection and linking
    if let urlPattern = try? NSRegularExpression(pattern: "(https?://[^\\s<>]+)", options: []) {
        let range = NSRange(result.startIndex..., in: result)
        result = urlPattern.stringByReplacingMatches(
            in: result,
            options: [],
            range: range,
            withTemplate: "<a href=\"$1\">$1</a>"
        )
    }

    return result
}

// MARK: - Service Message Text

private func serviceMessageText(_ message: Message) -> String? {
    for media in message.media {
        if let action = media as? TelegramMediaAction {
            switch action.action {
            case let .groupCreated(title):
                let authorName = peerDisplayName(message.author)
                return "\(htmlEscape(authorName)) created group &laquo;\(htmlEscape(title))&raquo;"
            case .pinnedMessageUpdated:
                let authorName = peerDisplayName(message.author)
                return "\(htmlEscape(authorName)) pinned a message"
            case let .addedMembers(peerIds):
                let authorName = peerDisplayName(message.author)
                let memberNames = peerIds.compactMap { id -> String? in
                    if let peer = message.peers[id] {
                        return peerDisplayName(peer)
                    }
                    return nil
                }
                if memberNames.isEmpty {
                    return "\(htmlEscape(authorName)) added members"
                }
                return "\(htmlEscape(authorName)) added \(memberNames.map { htmlEscape($0) }.joined(separator: ", "))"
            case let .removedMembers(peerIds):
                let authorName = peerDisplayName(message.author)
                let memberNames = peerIds.compactMap { id -> String? in
                    if let peer = message.peers[id] {
                        return peerDisplayName(peer)
                    }
                    return nil
                }
                if memberNames.isEmpty {
                    return "\(htmlEscape(authorName)) removed a member"
                }
                return "\(htmlEscape(authorName)) removed \(memberNames.map { htmlEscape($0) }.joined(separator: ", "))"
            case .joinedByLink:
                let authorName = peerDisplayName(message.author)
                return "\(htmlEscape(authorName)) joined group by link"
            case let .photoUpdated(photo):
                let authorName = peerDisplayName(message.author)
                if photo != nil {
                    return "\(htmlEscape(authorName)) changed group photo"
                }
                return "\(htmlEscape(authorName)) removed group photo"
            case let .titleUpdated(title):
                let authorName = peerDisplayName(message.author)
                return "\(htmlEscape(authorName)) changed group name to &laquo;\(htmlEscape(title))&raquo;"
            case .historyCleared:
                return "History cleared"
            case let .channelMigratedFromGroup(title, _):
                return "Group &laquo;\(htmlEscape(title))&raquo; converted to supergroup"
            case .groupMigratedToChannel:
                return "Group converted to supergroup"
            case let .topicCreated(title, _, _):
                return "Topic &laquo;\(htmlEscape(title))&raquo; created"
            case let .phoneCall(_, _, duration, isVideo):
                let authorName = peerDisplayName(message.author)
                let callType = isVideo ? "video call" : "call"
                if let duration = duration, duration > 0 {
                    return "\(htmlEscape(authorName)) made a \(callType) (\(formatDuration(Int(duration))))"
                }
                return "\(htmlEscape(authorName)) made a \(callType)"
            default:
                return nil
            }
        }
    }
    return nil
}

// MARK: - HTML Page Generation

private func htmlHeader(chatName: String) -> String {
    return """
    <!DOCTYPE html>
    <html>
     <head>
      <meta charset="utf-8"/>
      <title>Exported Data</title>
      <meta content="width=device-width, initial-scale=1.0" name="viewport"/>
      <link href="css/style.css" rel="stylesheet"/>
      <script src="js/script.js" type="text/javascript"></script>
     </head>
     <body onload="CheckLocation();">
      <div class="page_wrap">
       <div class="page_header">
        <div class="content">
         <div class="text bold">\(htmlEscape(chatName))</div>
        </div>
       </div>
       <div class="page_body chat_page">
        <div class="history">
    """
}

private func htmlFooter() -> String {
    return """
        </div>
       </div>
      </div>
     </body>
    </html>
    """
}

// MARK: - Export Engine

public struct SGChatExport {

    public static func exportChat(
        peerId: PeerId,
        postbox: Postbox,
        mediaBox: MediaBox
    ) -> Signal<SGChatExportProgress, NoError> {
        return Signal { subscriber in
            subscriber.putNext(.preparing)

            let disposable = postbox.transaction { transaction -> Void in
                let title = chatTitle(peerId: peerId, transaction: transaction)

                // Collect all messages
                var allMessages: [Message] = []
                transaction.withAllMessages(peerId: peerId, namespace: 0) { message in
                    allMessages.append(message)
                    return true
                }
                allMessages.sort { $0.timestamp < $1.timestamp }

                let totalMessages = allMessages.count
                if totalMessages == 0 {
                    subscriber.putNext(.error("No messages to export"))
                    subscriber.putCompletion()
                    return
                }

                // Create export directory
                let exportDirName = "ChatExport_\(title.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_"))"
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(exportDirName, isDirectory: true)

                // Clean up previous export
                try? FileManager.default.removeItem(at: tempDir)

                do {
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("css"), withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("js"), withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("photos"), withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("video_files"), withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("voice_messages"), withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("round_video_messages"), withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("stickers"), withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("files"), withIntermediateDirectories: true)
                } catch {
                    subscriber.putNext(.error("Failed to create export directory: \(error.localizedDescription)"))
                    subscriber.putCompletion()
                    return
                }

                // Write CSS and JS
                do {
                    try sgChatExportCSS.write(to: tempDir.appendingPathComponent("css/style.css"), atomically: true, encoding: .utf8)
                    try sgChatExportJS.write(to: tempDir.appendingPathComponent("js/script.js"), atomically: true, encoding: .utf8)
                } catch {
                    subscriber.putNext(.error("Failed to write assets: \(error.localizedDescription)"))
                    subscriber.putCompletion()
                    return
                }

                // Split into pages
                let totalPages = max(1, (totalMessages + messagesPerPage - 1) / messagesPerPage)
                var mediaFilesToCopy: [(source: String, destination: URL)] = []

                for pageIndex in 0..<totalPages {
                    let startIdx = pageIndex * messagesPerPage
                    let endIdx = min(startIdx + messagesPerPage, totalMessages)
                    let pageMessages = Array(allMessages[startIdx..<endIdx])

                    let fileName = pageIndex == 0 ? "messages.html" : "messages\(pageIndex + 1).html"
                    let prevFileName = pageIndex == 1 ? "messages.html" : (pageIndex > 1 ? "messages\(pageIndex).html" : nil)
                    let nextFileName = pageIndex < totalPages - 1 ? "messages\(pageIndex + 2).html" : nil

                    var html = htmlHeader(chatName: title)

                    // Add "Previous messages" pagination link
                    if let prevFileName = prevFileName {
                        html += "     <a class=\"pagination block_link\" href=\"\(prevFileName)\">Previous messages</a>\n\n"
                    }

                    var lastAuthorId: PeerId?
                    var lastDateStr: String?
                    var dateSeparatorId = -(pageIndex * 100 + 1)

                    for (msgIdx, message) in pageMessages.enumerated() {
                        let globalIdx = startIdx + msgIdx
                        subscriber.putNext(.exporting(current: globalIdx + 1, total: totalMessages))

                        let messageDate = Date(timeIntervalSince1970: Double(message.timestamp))
                        let currentDateStr = dateSeparatorFormatter.string(from: messageDate)

                        // Date separator
                        if currentDateStr != lastDateStr {
                            lastDateStr = currentDateStr
                            lastAuthorId = nil
                            html += """
                                 <div class="message service" id="message\(dateSeparatorId)">
                                  <div class="body details">\(currentDateStr)</div>
                                 </div>

                            """
                            dateSeparatorId -= 1
                        }

                        // Service message
                        if let serviceText = serviceMessageText(message) {
                            lastAuthorId = nil
                            html += """
                                 <div class="message service" id="message\(message.id.id)">
                                  <div class="body details">\(serviceText)</div>
                                 </div>

                            """
                            continue
                        }

                        // Regular message
                        let author = message.author
                        let authorId = author?.id
                        let isJoined = authorId == lastAuthorId && message.forwardInfo == nil
                        let joinedClass = isJoined ? " joined" : ""

                        let dateTitle = dateFormatter.string(from: messageDate) + " " + timeZoneSuffix()
                        let timeStr = timeFormatter.string(from: messageDate)

                        // Get media info
                        let mediaInfo = mediaInfoForMessage(message, mediaBox: mediaBox, messageDate: messageDate)
                        if let info = mediaInfo, let sourcePath = info.sourceResourcePath {
                            let destURL = tempDir
                                .appendingPathComponent(info.exportSubdir)
                                .appendingPathComponent(info.exportFileName)
                            mediaFilesToCopy.append((source: sourcePath, destination: destURL))

                            // For photos, also create a "thumb" copy
                            if info.exportSubdir == "photos" {
                                let thumbName = info.exportFileName.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
                                let thumbURL = tempDir
                                    .appendingPathComponent(info.exportSubdir)
                                    .appendingPathComponent(thumbName)
                                mediaFilesToCopy.append((source: sourcePath, destination: thumbURL))
                            }
                        }

                        let textContent = processMessageText(message.text)
                        let replyBlock = replyHTML(for: message)
                        let reactionsBlock = reactionsHTML(for: message)

                        html += "     <div class=\"message default clearfix\(joinedClass)\" id=\"message\(message.id.id)\">\n"

                        // Userpic (only for non-joined messages)
                        if !isJoined {
                            let initial = peerInitial(author)
                            let colorIdx = userpicColorIndex(author)
                            html += """
                                  <div class="pull_left userpic_wrap">
                                   <div class="userpic userpic\(colorIdx)" style="width: 42px; height: 42px">
                                    <div class="initials" style="line-height: 42px">\(htmlEscape(initial))</div>
                                   </div>
                                  </div>

                            """
                        }

                        html += "      <div class=\"body\">\n"
                        html += "       <div class=\"pull_right date details\" title=\"\(dateTitle)\">\(timeStr)</div>\n"

                        // Author name (only for non-joined messages)
                        if !isJoined {
                            let authorName = htmlEscape(peerDisplayName(author))
                            html += "       <div class=\"from_name\">\(authorName)</div>\n"
                        }

                        // Reply
                        if !replyBlock.isEmpty {
                            html += replyBlock + "\n"
                        }

                        // Forwarded message
                        if message.forwardInfo != nil {
                            let fwdBlock = forwardHTML(
                                message,
                                mediaHTML: mediaInfo?.htmlBlock ?? "",
                                textHTML: textContent
                            )
                            html += fwdBlock
                        } else {
                            // Media
                            if let mediaBlock = mediaInfo?.htmlBlock {
                                html += mediaBlock + "\n"
                            }
                            // Text
                            if !textContent.isEmpty {
                                html += "       <div class=\"text\">\(textContent)</div>\n"
                            }
                        }

                        // Reactions
                        if !reactionsBlock.isEmpty {
                            html += reactionsBlock
                        }

                        html += "      </div>\n"
                        html += "     </div>\n\n"

                        lastAuthorId = authorId
                    }

                    // Add "Next messages" pagination link
                    if let nextFileName = nextFileName {
                        html += "     <a class=\"pagination block_link\" href=\"\(nextFileName)\">Next messages</a>\n\n"
                    }

                    html += htmlFooter()

                    do {
                        let filePath = tempDir.appendingPathComponent(fileName)
                        try html.write(to: filePath, atomically: true, encoding: .utf8)
                    } catch {
                        subscriber.putNext(.error("Failed to write \(fileName): \(error.localizedDescription)"))
                        subscriber.putCompletion()
                        return
                    }
                }

                // Copy media files
                for (idx, mediaCopy) in mediaFilesToCopy.enumerated() {
                    subscriber.putNext(.copyingMedia(current: idx + 1, total: mediaFilesToCopy.count))
                    do {
                        if !FileManager.default.fileExists(atPath: mediaCopy.destination.path) {
                            try FileManager.default.copyItem(atPath: mediaCopy.source, toPath: mediaCopy.destination.path)
                        }
                    } catch {
                        #if canImport(SGLogging)
                        SGLogger.shared.log("SGChatExport", "Failed to copy media: \(error.localizedDescription)")
                        #endif
                    }
                }

                subscriber.putNext(.done(tempDir))
                subscriber.putCompletion()
            }.start()

            return ActionDisposable {
                disposable.dispose()
            }
        }
    }
}
