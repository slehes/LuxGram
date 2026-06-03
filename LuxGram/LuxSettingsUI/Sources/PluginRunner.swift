//
// Sets SGPluginHooks.messageHookRunner so that outgoing messages are passed to Python plugins.
// Requires PythonKit (https://github.com/pvieito/PythonKit). Add via SPM or embed for macOS/simulator.
// On iOS device, embed a Python framework (e.g. BeeWare) for full support.

import Foundation
import SGSimpleSettings

#if canImport(PythonKit)
import PythonKit
#endif

private let basePluginSource = """
from enum import Enum
from typing import Any, Optional

class HookStrategy(str, Enum):
    PASS = "PASS"
    MODIFY = "MODIFY"
    CANCEL = "CANCEL"

class HookResult:
    def __init__(self, strategy=None, params=None):
        self.strategy = strategy if strategy is not None else HookStrategy.PASS
        self.params = params

class BasePlugin:
    def __init__(self):
        self._hooks = set()

    def on_plugin_load(self):
        pass

    def add_on_send_message_hook(self):
        self._hooks.add("on_send_message_hook")

    def add_hook(self, name):
        self._hooks.add(name)

    def on_update_hook(self, update_name, account, update):
        pass

    def get_setting(self, key, default=None):
        try:
            return _get_setting(key, default)
        except NameError:
            return default

    def set_setting(self, key, value):
        try:
            _set_setting(key, value)
        except NameError:
            pass

    def _has_hook(self, name):
        return name in self._hooks
"""

/// Call once at app startup to install the Python-based message hook runner (when PythonKit is available).
public enum PluginRunner {
    private static var incomingMessageObserver: NSObjectProtocol?

    public static func install() {
        #if canImport(PythonKit)
        SGPluginHooks.messageHookRunner = { accountPeerId, peerId, text, replyToMessageId, replyMessageInfo in
            runPluginsSendMessageHook(accountPeerId: accountPeerId, peerId: peerId, text: text, replyToMessageId: replyToMessageId, replyMessageInfo: replyMessageInfo)
        }
        SGPluginHooks.incomingMessageHookRunner = { accountId, peerId, messageId, text, outgoing in
            runPluginsIncomingMessageHook(accountId: accountId, peerId: peerId, messageId: messageId, text: text, outgoing: outgoing)
        }
        #else
        SGPluginHooks.messageHookRunner = nil
        SGPluginHooks.incomingMessageHookRunner = nil
        #endif

        SGPluginHooks.userDisplayRunner = applyUserDisplayFromPlugins

        PluginRunner.incomingMessageObserver = NotificationCenter.default.addObserver(forName: SGPluginIncomingMessageNotificationName, object: nil, queue: .main) { note in
            guard let u = note.userInfo,
                  let accountId = u["accountId"] as? Int64,
                  let peerId = u["peerId"] as? Int64,
                  let messageId = u["messageId"] as? Int64,
                  let outgoing = u["outgoing"] as? Bool else { return }
            let text = u["text"] as? String
            SGPluginHooks.incomingMessageHookRunner?(accountId, peerId, messageId, text, outgoing)
        }
    }
}

// MARK: - User display plugins (__user_display__ = True) — generic runner, no app code changes per plugin
private func applyUserDisplayFromPlugins(accountId: Int64, user: PluginDisplayUser) -> PluginDisplayUser? {
    guard SGSimpleSettings.shared.pluginSystemEnabled,
          let data = SGSimpleSettings.shared.installedPluginsJson.data(using: .utf8),
          let plugins = try? JSONDecoder().decode([PluginInfo].self, from: data) else {
        return nil
    }
    let host = PluginHost.shared
    for plugin in plugins where plugin.enabled && plugin.metadata.hasUserDisplay {
        let pluginId = plugin.metadata.id
        guard host.getPluginSettingBool(pluginId: pluginId, key: "enabled", default: false) else { continue }
        let targetIdStr = host.getPluginSetting(pluginId: pluginId, key: "target_user_id")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetUserId: Int64
        if targetIdStr.isEmpty {
            targetUserId = accountId
        } else if let parsed = Int64(targetIdStr) {
            targetUserId = parsed
        } else {
            continue
        }
        if user.id != targetUserId { continue }
        func s(_ key: String) -> String? {
            host.getPluginSetting(pluginId: pluginId, key: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let firstName = s("fake_first_name").flatMap { $0.isEmpty ? nil : $0 } ?? user.firstName
        let lastName = s("fake_last_name").flatMap { $0.isEmpty ? nil : $0 } ?? user.lastName
        let username = s("fake_username").flatMap { $0.isEmpty ? nil : $0 } ?? user.username
        let phone = s("fake_phone").flatMap { $0.isEmpty ? nil : $0 } ?? user.phone
        let id: Int64 = s("fake_id").flatMap { $0.isEmpty ? nil : Int64($0) } ?? user.id
        let isPremium = host.getPluginSettingBool(pluginId: pluginId, key: "fake_premium", default: user.isPremium)
        let isVerified = host.getPluginSettingBool(pluginId: pluginId, key: "fake_verified", default: user.isVerified)
        let isScam = host.getPluginSettingBool(pluginId: pluginId, key: "fake_scam", default: user.isScam)
        let isFake = host.getPluginSettingBool(pluginId: pluginId, key: "fake_fake", default: user.isFake)
        let isSupport = host.getPluginSettingBool(pluginId: pluginId, key: "fake_support", default: user.isSupport)
        let isBot = host.getPluginSettingBool(pluginId: pluginId, key: "fake_bot", default: user.isBot)
        return PluginDisplayUser(
            firstName: firstName,
            lastName: lastName,
            username: username,
            phone: phone,
            id: id,
            isPremium: isPremium,
            isVerified: isVerified,
            isScam: isScam,
            isFake: isFake,
            isSupport: isSupport,
            isBot: isBot
        )
    }
    return nil
}

#if canImport(PythonKit)
private func runPluginsSendMessageHook(accountPeerId: Int64, peerId: Int64, text: String, replyToMessageId: Int64?, replyMessageInfo: ReplyMessageInfo?) -> SGPluginHookResult? {
    guard let data = SGSimpleSettings.shared.installedPluginsJson.data(using: .utf8),
          let plugins = try? JSONDecoder().decode([PluginInfo].self, from: data) else {
        return nil
    }
    let enabled = plugins.filter { $0.enabled }
    guard !enabled.isEmpty else { return nil }

    let replyId = Int(replyToMessageId ?? 0)
    let accountId = Int(accountPeerId)
    let peerIdInt = Int(peerId)

    for pluginInfo in enabled {
        let pluginId = pluginInfo.metadata.id
        guard let content = try? String(contentsOfFile: pluginInfo.path, encoding: .utf8) else { continue }

        let builtins = Python.import("builtins")
        let globals = Python.dict()
        do {
            try builtins.exec.thunk.call(PythonObject(basePluginSource), globals, globals)
            try builtins.exec.thunk.call(PythonObject(content), globals, globals)
        } catch {
            continue
        }

        guard let bp = globals["BasePlugin"], bp.isNone == false else { continue }
        let findClassCode = """
_plugin_cls = None
for _n, _o in list(globals().items()):
    if _n != 'BasePlugin' and isinstance(_o, type) and issubclass(_o, BasePlugin):
        _plugin_cls = _o
        break
"""
        try? builtins.exec.thunk.call(PythonObject(findClassCode), globals, globals)
        guard let cls = globals["_plugin_cls"], cls.isNone == false else { continue }

        let instance: PythonObject
        do {
            instance = try cls.call()
        } catch {
            continue
        }
        _ = try? instance.on_plugin_load.call()
        let hasHook = instance._has_hook.call("on_send_message_hook")
        guard hasHook.bool == true else { continue }

        // Build params object in Python (message, peer, replyToMsg; reply message document info for FileViewer-style plugins)
        globals["_msg_text"] = PythonObject(text)
        globals["_msg_peer"] = PythonObject(peerIdInt)
        globals["_msg_reply"] = PythonObject(replyId)
        globals["_msg_reply_id"] = PythonObject(Int(replyMessageInfo?.messageId ?? 0))
        globals["_msg_reply_is_doc"] = PythonObject(replyMessageInfo?.isDocument ?? false)
        globals["_msg_reply_file_path"] = replyMessageInfo?.filePath.map { PythonObject($0) } ?? Python.None
        globals["_msg_reply_file_name"] = replyMessageInfo?.fileName.map { PythonObject($0) } ?? Python.None
        globals["_msg_reply_mime"] = replyMessageInfo?.mimeType.map { PythonObject($0) } ?? Python.None
        let paramsCode = """
class _Params:
    pass
class _ReplyMsg:
    pass
_params_obj = _Params()
_params_obj.message = _msg_text
_params_obj.peer = _msg_peer
_params_obj.replyToMsgId = _msg_reply
_params_obj.replyToMsg = _ReplyMsg()
_params_obj.replyToMsg.id = _msg_reply_id
_params_obj.replyToMsg.messageOwner = _ReplyMsg()
_params_obj.replyToMsg.messageOwner.id = _msg_reply_id
_params_obj.replyToMsg.isDocument = _msg_reply_is_doc
_params_obj.replyToMsg.filePath = _msg_reply_file_path
_params_obj.replyToMsg.fileName = _msg_reply_file_name
_params_obj.replyToMsg.mimeType = _msg_reply_mime
"""
        try? builtins.exec.thunk.call(PythonObject(paramsCode), globals, globals)
        guard let paramsObj = globals["_params_obj"], paramsObj.isNone == false else { continue }

        let result: PythonObject
        do {
            result = try instance.on_send_message_hook.call(accountId, paramsObj)
        } catch {
            continue
        }

        guard let strategyObj = result.strategy, strategyObj.isNone == false else { continue }
        let strategyStr = String(strategyObj) ?? "PASS"
        if strategyStr == "CANCEL" {
            return SGPluginHookResult(strategy: .cancel, message: nil)
        }
        if strategyStr == "MODIFY" {
            var newMessage = text
            if let p = result.params, p.isNone == false, let msg = p.message, msg.isNone == false {
                newMessage = String(msg) ?? text
            }
            return SGPluginHookResult(strategy: .modify, message: newMessage)
        }
    }
    return nil
}

private func runPluginsIncomingMessageHook(accountId: Int64, peerId: Int64, messageId: Int64, text: String?, outgoing: Bool) {
    guard SGSimpleSettings.shared.pluginSystemEnabled,
          let data = SGSimpleSettings.shared.installedPluginsJson.data(using: .utf8),
          let plugins = try? JSONDecoder().decode([PluginInfo].self, from: data) else { return }
    let enabled = plugins.filter { $0.enabled }
    guard !enabled.isEmpty else { return }

    let accountIdInt = Int(accountId)
    let peerIdInt = Int(peerId)
    let messageIdInt = Int(messageId)
    let textPy = text.map { PythonObject($0) } ?? Python.None
    let outgoingPy = PythonObject(outgoing)

    for pluginInfo in enabled {
        guard let content = try? String(contentsOfFile: pluginInfo.path, encoding: .utf8) else { continue }
        let builtins = Python.import("builtins")
        let globals = Python.dict()
        do {
            try builtins.exec.thunk.call(PythonObject(basePluginSource), globals, globals)
            try builtins.exec.thunk.call(PythonObject(content), globals, globals)
        } catch { continue }
        guard let bp = globals["BasePlugin"], bp.isNone == false else { continue }
        let findClassCode = """
_plugin_cls = None
for _n, _o in list(globals().items()):
    if _n != 'BasePlugin' and isinstance(_o, type) and issubclass(_o, BasePlugin):
        _plugin_cls = _o
        break
"""
        try? builtins.exec.thunk.call(PythonObject(findClassCode), globals, globals)
        guard let cls = globals["_plugin_cls"], cls.isNone == false else { continue }
        let instance: PythonObject
        do { instance = try cls.call() } catch { continue }
        _ = try? instance.on_plugin_load.call()
        let hasNewMessage = instance._has_hook.call("updateNewMessage").bool == true
        let hasChannelMessage = instance._has_hook.call("updateNewChannelMessage").bool == true
        guard hasNewMessage || hasChannelMessage else { continue }
        let updateName = hasChannelMessage ? "updateNewChannelMessage" : "updateNewMessage"
        globals["_upd_message"] = textPy
        globals["_upd_peer"] = PythonObject(peerIdInt)
        globals["_upd_msg_id"] = PythonObject(messageIdInt)
        globals["_upd_outgoing"] = outgoingPy
        let paramsCode = """
class _UpdateObj:
    pass
_update_obj = _UpdateObj()
_update_obj.message = _upd_message
_update_obj.peer = _upd_peer
_update_obj.message_id = _upd_msg_id
_update_obj.outgoing = _upd_outgoing
"""
        try? builtins.exec.thunk.call(PythonObject(paramsCode), globals, globals)
        guard let updateObj = globals["_update_obj"], updateObj.isNone == false else { continue }
        _ = try? instance.on_update_hook.call(updateName, accountIdInt, updateObj)
    }
}
#endif
