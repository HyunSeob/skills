// Template for one native AX helper action. Copy it per app and replace the TODO lookups.
//
//   swiftc -O helper_action.swift -o "$TMPDIR/myapp_action"
//   echo '{"bundleId":"com.example.App","windowTitle":"Exact title","action":"inspect"}' | "$TMPDIR/myapp_action"
//
// Contract:
// - Request JSON on stdin (user text never goes through argv). One JSON object on stdout.
// - Elements are resolved fresh on every call: no stored coordinates, row indices or element refs.
// - Every target must be unique; otherwise the helper stops with a reason code.
// - "press" performs AXPress exactly once and never retries, even when it reports an error:
//   the app may already have handled it. The caller confirms by reading the UI again.
import AppKit
import ApplicationServices
import Foundation

enum Failure: Error { case blocked(String) }

let started = ProcessInfo.processInfo.systemUptime
let deadline = started + 8.0
var visited = 0
var dispatchAttempted = false
var actionLog: [[String: Any]] = []

// TODO: labels differ per UI language; prefer AXIdentifier when the app sets one.
let targetButtonIdentifiers: [String] = []
let targetButtonLabels = ["보내기", "전송", "Send"]
let composerLabels = ["메시지 입력", "Message"]

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
}
func string(_ el: AXUIElement, _ name: String) -> String {
    let value = attr(el, name)
    if let text = value as? String { return text }
    if let text = value as? NSAttributedString { return text.string }
    return ""
}
func children(_ el: AXUIElement, _ name: String = "AXChildren") -> [AXUIElement] {
    attr(el, name) as? [AXUIElement] ?? []
}
func actionNames(_ el: AXUIElement) -> [String] {
    var value: CFArray?
    _ = AXUIElementCopyActionNames(el, &value)
    return value as? [String] ?? []
}
func settable(_ el: AXUIElement, _ name: String) -> Bool {
    var result = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(el, name as CFString, &result) == .success && result.boolValue
}
func textValue(_ el: AXUIElement) throws -> String {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(el, "AXValue" as CFString, &value)
    if result == .noValue { return "" }
    guard result == .success else { throw Failure.blocked("text_value_unavailable") }
    if let text = value as? String { return text }
    if let text = value as? NSAttributedString { return text.string }
    throw Failure.blocked("text_value_unavailable")
}

// Walk controls only. Skip list/table contents the action does not need, and stop on modals.
func controls(_ el: AXUIElement, depth: Int = 0) throws -> [AXUIElement] {
    visited += 1
    guard visited <= 2000, depth <= 15, ProcessInfo.processInfo.systemUptime < deadline else {
        throw Failure.blocked("control_tree_limit")
    }
    let role = string(el, "AXRole")
    if ["AXSheet", "AXDialog"].contains(role) { throw Failure.blocked("modal_dialog_present") }
    if ["AXTable", "AXOutline", "AXRow", "AXCell"].contains(role) { return [el] }
    var result = [el]
    for child in children(el) { result += try controls(child, depth: depth + 1) }
    return result
}

func unique(_ found: [AXUIElement], _ reason: String) throws -> AXUIElement {
    guard found.count == 1 else { throw Failure.blocked(found.isEmpty ? "\(reason)_not_found" : "\(reason)_not_unique") }
    return found[0]
}

func targetWindow(_ app: AXUIElement, _ title: String) throws -> AXUIElement {
    let window = try unique(children(app, "AXWindows").filter { string($0, "AXTitle") == title }, "target_window")
    guard children(window, "AXSheets").isEmpty else { throw Failure.blocked("modal_dialog_present") }
    return window
}

func targetButton(_ nodes: [AXUIElement]) throws -> AXUIElement {
    // TODO: narrow by the button's real role/identifier from ax_dump.
    let button = try unique(nodes.filter {
        string($0, "AXRole") == "AXButton" &&
        (targetButtonIdentifiers.contains(string($0, "AXIdentifier")) ||
         targetButtonLabels.contains(string($0, "AXTitle")) || targetButtonLabels.contains(string($0, "AXDescription")))
    }, "target_button")
    guard actionNames(button).contains("AXPress") else { throw Failure.blocked("target_button_has_no_axpress") }
    return button
}

// Draft guard: never act over text the user was typing.
func requireEmptyComposer(_ nodes: [AXUIElement]) throws {
    let composers = nodes.filter { string($0, "AXRole") == "AXTextArea" && composerLabels.contains(string($0, "AXDescription")) }
    for composer in composers where try !textValue(composer).isEmpty {
        throw Failure.blocked("existing_draft_preserved")
    }
}

// Setting AXValue alone often changes only the displayed string; the app's search logic
// listens for edits. Focus, select all, replace the selection, then confirm and wait.
func editSearchField(_ field: AXUIElement, _ query: String, settle: TimeInterval = 0.65) throws {
    guard ["AXTextField", "AXSearchField"].contains(string(field, "AXRole")) else {
        throw Failure.blocked("only_search_fields_may_be_edited")
    }
    if settable(field, "AXFocused") {
        let focused = AXUIElementSetAttributeValue(field, "AXFocused" as CFString, kCFBooleanTrue)
        actionLog.append(["action": "AXFocused", "result": Int(focused.rawValue)])
    }
    guard settable(field, "AXSelectedTextRange"), settable(field, "AXSelectedText") else {
        throw Failure.blocked("search_text_edit_not_supported")
    }
    var range = CFRange(location: 0, length: string(field, "AXValue").utf16.count)
    guard let rangeValue = AXValueCreate(.cfRange, &range) else { throw Failure.blocked("search_selection_unavailable") }
    let selected = AXUIElementSetAttributeValue(field, "AXSelectedTextRange" as CFString, rangeValue)
    actionLog.append(["action": "AXSelectedTextRange", "result": Int(selected.rawValue)])
    guard selected == .success else { throw Failure.blocked("search_selection_failed") }
    let edited = AXUIElementSetAttributeValue(field, "AXSelectedText" as CFString, query as CFString)
    actionLog.append(["action": "AXSelectedText", "result": Int(edited.rawValue)])
    guard edited == .success, string(field, "AXValue") == query else { throw Failure.blocked("search_text_edit_failed") }
    if actionNames(field).contains("AXConfirm") {
        let confirmed = AXUIElementPerformAction(field, "AXConfirm" as CFString)
        actionLog.append(["action": "AXConfirm", "result": Int(confirmed.rawValue)])
    }
    // Apps debounce search input; reading immediately returns the previous query's results.
    Thread.sleep(forTimeInterval: settle)
}

func run() throws -> [String: Any] {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 64 * 1024,
          let request = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
          let bundleId = request["bundleId"] as? String, !bundleId.isEmpty,
          let title = request["windowTitle"] as? String, !title.isEmpty,
          let action = request["action"] as? String, ["inspect", "search", "press"].contains(action) else {
        throw Failure.blocked("invalid_request")
    }
    guard AXIsProcessTrusted() else { throw Failure.blocked("accessibility_permission_required") }
    guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
        throw Failure.blocked("app_not_running")
    }
    let app = AXUIElementCreateApplication(running.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.25)
    let window = try targetWindow(app, title)

    if action == "search" {
        guard let query = request["query"] as? String, query.utf8.count <= 4096 else { throw Failure.blocked("invalid_query") }
        let field = try unique(try controls(window).filter { ["AXTextField", "AXSearchField"].contains(string($0, "AXRole")) }, "search_field")
        try editSearchField(field, query)
        return ["status": "ok", "query": string(field, "AXValue")]
    }

    var nodes = try controls(window)
    try requireEmptyComposer(nodes)
    var button = try targetButton(nodes)
    if action == "inspect" {
        return ["status": "ready", "buttonEnabled": (attr(button, "AXEnabled") as? Bool) ?? false]
    }
    // Re-resolve right before acting and re-check every precondition.
    nodes = try controls(try targetWindow(app, title))
    button = try targetButton(nodes)
    guard (attr(button, "AXEnabled") as? Bool) == true else { throw Failure.blocked("target_button_disabled") }
    dispatchAttempted = true
    let result = AXUIElementPerformAction(button, "AXPress" as CFString)
    actionLog.append(["action": "AXPress", "result": Int(result.rawValue)])
    // Even kAXErrorFailure (-25200) does not prove nothing happened. Do not retry here.
    return ["status": result == .success ? "dispatch_attempted" : "dispatch_result_unknown", "axResult": Int(result.rawValue)]
}

var report: [String: Any]
do {
    report = try run()
} catch Failure.blocked(let reason) {
    report = ["status": "blocked", "reason": reason]
} catch {
    report = ["status": "bridge_error"]
}
report["dispatchAttempted"] = dispatchAttempted
report["actions"] = actionLog
report["visitedNodes"] = visited
report["elapsedMs"] = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
   let line = String(data: data, encoding: .utf8) {
    print(line)
}
