// Dump a running macOS app's accessibility (AX) tree as indented text or JSON.
//
//   swiftc -O ax_dump.swift -o "$TMPDIR/ax_dump"
//   "$TMPDIR/ax_dump" --list-apps
//   "$TMPDIR/ax_dump" --app com.apple.Notes [--window TITLE] [--depth 8] [--max-nodes 3000]
//                     [--values none|short|full] [--json] [--prompt]
//
// Read-only: it never sets attributes or performs actions. Large tables and outlines are
// walked through AXVisibleRows only, with the reported total row count printed beside them.
import AppKit
import ApplicationServices
import Foundation

struct Options {
    var app = ""
    var window = ""
    var depth = 8
    var maxNodes = 3000
    var values = "short"
    var json = false
    var listApps = false
    var prompt = false
}

func fail(_ message: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

func parse() -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    func next(_ flag: String) -> String {
        guard !args.isEmpty else { fail("missing value for \(flag)") }
        return args.removeFirst()
    }
    while !args.isEmpty {
        let flag = args.removeFirst()
        switch flag {
        case "--app": options.app = next(flag)
        case "--window": options.window = next(flag)
        case "--depth": options.depth = Int(next(flag)) ?? options.depth
        case "--max-nodes": options.maxNodes = Int(next(flag)) ?? options.maxNodes
        case "--values":
            options.values = next(flag)
            guard ["none", "short", "full"].contains(options.values) else { fail("--values must be none, short or full") }
        case "--json": options.json = true
        case "--list-apps": options.listApps = true
        case "--prompt": options.prompt = true
        case "-h", "--help":
            print("usage: ax_dump --list-apps | --app BUNDLE_ID_OR_NAME [--window TITLE] [--depth N] [--max-nodes N] [--values none|short|full] [--json] [--prompt]")
            exit(0)
        default: fail("unknown argument \(flag)")
        }
    }
    return options
}

let options = parse()

if options.listApps {
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        print("\(app.bundleIdentifier ?? "-")\t\(app.localizedName ?? "-")\tpid=\(app.processIdentifier)")
    }
    exit(0)
}
guard !options.app.isEmpty else { fail("pass --app BUNDLE_ID_OR_NAME (see --list-apps)") }

if options.prompt {
    let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(prompt)
}
guard AXIsProcessTrusted() else {
    fail("accessibility_permission_required: enable this terminal or agent app in System Settings > Privacy & Security > Accessibility", 2)
}

let matches = NSWorkspace.shared.runningApplications.filter {
    $0.bundleIdentifier == options.app || $0.localizedName?.caseInsensitiveCompare(options.app) == .orderedSame
}
guard matches.count == 1 else {
    fail(matches.isEmpty ? "app_not_running: \(options.app)" : "app_ambiguous: \(matches.count) processes match \(options.app)")
}
let application = AXUIElementCreateApplication(matches[0].processIdentifier)
AXUIElementSetMessagingTimeout(application, 0.5)

let deadline = ProcessInfo.processInfo.systemUptime + 20
var visited = 0
var truncated = false
let names = ["AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXIdentifier", "AXHelp", "AXValue", "AXEnabled", "AXChildren"]
let probedSettable = ["AXValue", "AXFocused", "AXSelectedText", "AXSelectedTextRange"]

func describe(_ value: CFTypeRef) -> Any? {
    if CFGetTypeID(value) == CFNullGetTypeID() { return nil }
    if let text = value as? String { return text }
    if let text = value as? NSAttributedString { return text.string }
    if CFGetTypeID(value) == CFBooleanGetTypeID() { return (value as! Bool) }
    if let number = value as? NSNumber { return number }
    if CFGetTypeID(value) == AXValueGetTypeID() {
        let boxed = value as! AXValue
        switch AXValueGetType(boxed) {
        case .axError: return nil
        case .cgPoint: var p = CGPoint.zero; AXValueGetValue(boxed, .cgPoint, &p); return "(\(Int(p.x)),\(Int(p.y)))"
        case .cgSize: var s = CGSize.zero; AXValueGetValue(boxed, .cgSize, &s); return "\(Int(s.width))x\(Int(s.height))"
        case .cfRange: var r = CFRange(); AXValueGetValue(boxed, .cfRange, &r); return "range(\(r.location),\(r.length))"
        default: return "<AXValue>"
        }
    }
    return "<\(CFCopyTypeIDDescription(CFGetTypeID(value)) as String? ?? "value")>"
}

func batch(_ element: AXUIElement) -> [String: CFTypeRef] {
    // One IPC round trip per node instead of one per attribute.
    var copied: CFArray?
    guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &copied) == .success,
          let values = copied as? [CFTypeRef], values.count == names.count else { return [:] }
    var output: [String: CFTypeRef] = [:]
    for (index, name) in names.enumerated() { output[name] = values[index] }
    return output
}

func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement]? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? [AXUIElement]
}

func actions(_ element: AXUIElement) -> [String] {
    var value: CFArray?
    _ = AXUIElementCopyActionNames(element, &value)
    // Custom actions arrive as "Name:...\nTarget:...\nSelector:..."; keep only the name.
    return (value as? [String] ?? []).map { action in
        guard action.hasPrefix("Name:") else { return action }
        return "custom:" + String(action.dropFirst(5).prefix { $0 != "\n" })
    }
}

func settable(_ element: AXUIElement) -> [String] {
    probedSettable.filter {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, $0 as CFString, &result) == .success && result.boolValue
    }
}

func clip(_ text: String) -> String? {
    switch options.values {
    case "none": return nil
    case "short": return text.count > 60 ? String(text.prefix(60)) + "…" : text
    default: return text
    }
}

func node(_ element: AXUIElement, depth: Int) -> [String: Any] {
    visited += 1
    let attributes = batch(element)
    var info: [String: Any] = [:]
    for name in ["AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXIdentifier", "AXHelp", "AXEnabled"] {
        if let raw = attributes[name], let value = describe(raw) {
            if let text = value as? String, text.isEmpty { continue }
            info[name] = value
        }
    }
    if let raw = attributes["AXValue"], let value = describe(raw) {
        if let text = value as? String {
            if !text.isEmpty, let shown = clip(text) { info["AXValue"] = shown }
        } else if options.values != "none" {
            info["AXValue"] = value
        }
    }
    let acts = actions(element)
    if !acts.isEmpty { info["actions"] = acts }
    let sets = settable(element)
    if !sets.isEmpty { info["settable"] = sets }

    let role = info["AXRole"] as? String ?? ""
    var children: [AXUIElement] = []
    if ["AXTable", "AXOutline", "AXList"].contains(role), let rows = elements(element, "AXVisibleRows") {
        // Offscreen rows are virtualized; fetching all of them can stall large apps.
        var count: CFIndex = 0
        if AXUIElementGetAttributeValueCount(element, "AXRows" as CFString, &count) == .success { info["reportedRows"] = count }
        info["childrenSource"] = "AXVisibleRows"
        children = rows
    } else if let raw = attributes["AXChildren"], let list = raw as? [AXUIElement] {
        children = list
    }
    if !children.isEmpty {
        if depth >= options.depth {
            info["childCount"] = children.count
        } else {
            var output: [[String: Any]] = []
            for child in children {
                guard visited < options.maxNodes, ProcessInfo.processInfo.systemUptime < deadline else {
                    truncated = true
                    break
                }
                output.append(node(child, depth: depth + 1))
            }
            info["children"] = output
        }
    }
    return info
}

func quote(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

func render(_ info: [String: Any], indent: Int) {
    var line = String(repeating: "  ", count: indent) + (info["AXRole"] as? String ?? "?")
    if let subrole = info["AXSubrole"] as? String { line += "[\(subrole)]" }
    if let title = info["AXTitle"] as? String { line += " " + quote(title) }
    if let text = info["AXDescription"] as? String { line += " desc=" + quote(text) }
    if let text = info["AXIdentifier"] as? String { line += " id=" + quote(text) }
    if let text = info["AXHelp"] as? String { line += " help=" + quote(text) }
    if let value = info["AXValue"] { line += " value=" + ((value as? String).map(quote) ?? "\(value)") }
    if (info["AXEnabled"] as? Bool) == false && info["AXRole"] as? String != "AXApplication" { line += " disabled" }
    if let list = info["actions"] as? [String] { line += " actions=[\(list.joined(separator: ","))]" }
    if let list = info["settable"] as? [String] { line += " settable=[\(list.joined(separator: ","))]" }
    if let rows = info["reportedRows"] { line += " rows=\(rows) (visible only)" }
    if let count = info["childCount"] { line += " …\(count) children (raise --depth)" }
    print(line)
    for child in info["children"] as? [[String: Any]] ?? [] { render(child, indent: indent + 1) }
}

var roots: [AXUIElement] = [application]
if !options.window.isEmpty {
    let windows = (elements(application, "AXWindows") ?? []).filter {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue($0, "AXTitle" as CFString, &value)
        return (value as? String) == options.window
    }
    guard windows.count == 1 else { fail(windows.isEmpty ? "window_not_found" : "window_ambiguous") }
    roots = windows
}

let tree = node(roots[0], depth: 0)
if options.json {
    let report: [String: Any] = ["app": matches[0].bundleIdentifier ?? options.app, "visitedNodes": visited,
                                 "truncated": truncated, "values": options.values, "tree": tree]
    let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
} else {
    render(tree, indent: 0)
    print("# visited=\(visited) truncated=\(truncated) values=\(options.values)")
}
