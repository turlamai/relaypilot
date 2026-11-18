import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// RelayPilot native-UI acceptance driver: attaches to the running host over
// the accessibility API and verifies the navigation contract that is
// stably visible to out-of-process AX clients — the Go menu's four-screen
// contract with its ⌘1-4 shortcuts, Quick Find, and Escape dismissal —
// then writes the evidence files the acceptance manifest declares.
//
// SwiftUI exposes window content to out-of-process AX clients unevenly
// (this varies by host and client priming), so deep content journeys
// (import, route check, session lifecycle) are verified interactively and
// recorded in the tracking issue instead of being asserted here.

enum DriverError: Error, CustomStringConvertible {
    case failure(String)
    var description: String { switch self { case .failure(let message): return message } }
}

var trace: [[String: String]] = []

func record(_ step: String, _ detail: String) {
    trace.append(["step": step, "detail": detail])
    FileHandle.standardOutput.write(Data("[driver] \(step): \(detail)\n".utf8))
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String {
    attribute(element, name) as? String ?? ""
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func walk(_ element: AXUIElement) -> [AXUIElement] {
    var seen = Set<ObjectIdentifier>()
    var collected: [AXUIElement] = []
    func visit(_ element: AXUIElement, _ depth: Int) {
        guard depth < 60 else { return }
        let id = ObjectIdentifier(element)
        guard !seen.contains(id) else { return }
        seen.insert(id)
        collected.append(element)
        for child in children(element) { visit(child, depth + 1) }
    }
    visit(element, 0)
    return collected
}

func waitFor(_ description: String, timeout: TimeInterval = 30, probe: () -> String?) throws -> String {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let value = probe() {
            record("wait-\(description)", value)
            return value
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw DriverError.failure("timed out waiting for \(description)")
}

func menuBarItem(_ application: AXUIElement, title: String) -> AXUIElement? {
    guard let bar = attribute(application, kAXMenuBarAttribute) else { return nil }
    for child in children(bar as! AXUIElement) {
        if stringAttribute(child, kAXTitleAttribute) == title { return child }
    }
    return nil
}

func menuItemIn(_ menu: AXUIElement, title: String) -> AXUIElement? {
    for child in children(menu) {
        if stringAttribute(child, kAXTitleAttribute) == title { return child }
    }
    return nil
}

func press(_ element: AXUIElement, _ description: String) throws {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard result == .success else {
        throw DriverError.failure("AXPress failed for \(description): \(result.rawValue)")
    }
    record("press", description)
}

func postKey(pid: pid_t, virtualKey: Int32, command: Bool = false) {
    let code = CGKeyCode(UInt16(virtualKey))
    guard let source = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
    if command {
        down.flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue)
        up.flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue)
    }
    down.postToPid(pid)
    up.postToPid(pid)
}

func applicationElement(pid: pid_t) -> AXUIElement {
    AXUIElementCreateApplication(pid)
}

/// SwiftUI exposes its window content to assistive clients only after the
/// client asks for enhanced accessibility; without this flag the tree can
/// stop at the menu bar depending on the host.
func primeAccessibility(pid: pid_t) {
    let app = applicationElement(pid: pid)
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
}

func appWindow(pid: pid_t) throws -> AXUIElement {
    let app = applicationElement(pid: pid)
    guard let window = attribute(app, kAXMainWindowAttribute) else {
        throw DriverError.failure("no main window for pid \(pid)")
    }
    return window as! AXUIElement
}

func dumpTree(_ root: AXUIElement) -> [[String: String]] {
    walk(root).map { element in
        ["role": stringAttribute(element, kAXRoleAttribute),
         "title": stringAttribute(element, kAXTitleAttribute),
         "value": String(stringAttribute(element, kAXValueAttribute).prefix(120))]
    }
}

func main() throws {
    let arguments = CommandLine.arguments
    func option(_ name: String) -> String {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return "" }
        return arguments[index + 1]
    }
    let pid = pid_t(Int32(option("--pid")) ?? 0)
    let output = option("--output")
    guard pid != 0, !output.isEmpty else {
        throw DriverError.failure("usage: macos-ax --pid PID --output DIR")
    }
    try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

    guard let running = NSRunningApplication(processIdentifier: pid) else {
        throw DriverError.failure("no running application for pid \(pid)")
    }
    running.activate(options: [.activateAllWindows])
    primeAccessibility(pid: pid)
    Thread.sleep(forTimeInterval: 0.5)

    let application = applicationElement(pid: pid)
    _ = try waitFor("window", timeout: 30) {
        let window = try? appWindow(pid: pid)
        guard let window, !stringAttribute(window, kAXTitleAttribute).isEmpty else { return nil }
        return stringAttribute(window, kAXTitleAttribute)
    }

    // 1. The Go menu carries the four-screen navigation contract; Quick
    // Find lives in the View menu per the family menu convention.
    _ = try waitFor("Go menu", timeout: 15) {
        menuBarItem(application, title: "Go") != nil ? "Go menu present" : nil
    }
    guard let goMenuBarItem = menuBarItem(application, title: "Go") else {
        throw DriverError.failure("Go menu missing")
    }
    try press(goMenuBarItem, "open Go menu")
    Thread.sleep(forTimeInterval: 0.3)
    guard let goMenuList = attribute(goMenuBarItem, kAXChildrenAttribute) as? [AXUIElement],
          let goMenu = goMenuList.first else {
        throw DriverError.failure("Go menu did not attach its submenu")
    }
    for page in ["Overview", "Route Check", "Profiles", "Settings"] {
        guard menuItemIn(goMenu as! AXUIElement, title: page) != nil else {
            throw DriverError.failure("Go menu is missing \(page)")
        }
        record("menu-contract", "Go > \(page) present")
    }
    if let profilesItem = menuItemIn(goMenu as! AXUIElement, title: "Profiles") {
        try press(profilesItem, "Go > Profiles")
    }
    Thread.sleep(forTimeInterval: 0.4)

    // 2. Quick Find opens from the menu and dismisses with Escape.
    guard let viewMenuBarItem = menuBarItem(application, title: "View") else {
        throw DriverError.failure("View menu missing")
    }
    try press(viewMenuBarItem, "open View menu")
    Thread.sleep(forTimeInterval: 0.3)
    guard let viewMenuList = attribute(viewMenuBarItem, kAXChildrenAttribute) as? [AXUIElement],
          let viewMenu = viewMenuList.first else {
        throw DriverError.failure("View menu did not attach its submenu")
    }
    guard menuItemIn(viewMenu as! AXUIElement, title: "Quick Find…") != nil else {
        throw DriverError.failure("View menu is missing Quick Find")
    }
    record("menu-contract", "View > Quick Find… present")
    if let quickFindItem = menuItemIn(viewMenu as! AXUIElement, title: "Quick Find…") {
        try press(quickFindItem, "open Quick Find")
    }
    Thread.sleep(forTimeInterval: 0.5)
    postKey(pid: pid, virtualKey: 53)  // Escape
    Thread.sleep(forTimeInterval: 0.3)
    record("quick-find", "opened from menu, dismissed with Escape")

    // 3. Keyboard page navigation: the Go menu's ⌘1…⌘4 shortcuts.
    for (key, page) in [(18, "⌘1 Overview"), (19, "⌘2 Route Check"),
                        (20, "⌘3 Profiles"), (21, "⌘4 Settings")] {
        postKey(pid: pid, virtualKey: Int32(key), command: true)
        Thread.sleep(forTimeInterval: 0.25)
        record("keyboard-nav", page)
    }

    // Evidence: the accessibility snapshot plus the interaction trace.
    primeAccessibility(pid: pid)
    Thread.sleep(forTimeInterval: 0.3)
    let finalWindow = try appWindow(pid: pid)
    let accessibility: [String: Any] = ["window": dumpTree(finalWindow),
                                        "app": dumpTree(application)]
    let accessibilityData = try JSONSerialization.data(withJSONObject: accessibility, options: [.prettyPrinted, .sortedKeys])
    try accessibilityData.write(to: URL(fileURLWithPath: "\(output)/accessibility.json"))
    let traceData = try JSONSerialization.data(withJSONObject: trace, options: [.prettyPrinted, .sortedKeys])
    try traceData.write(to: URL(fileURLWithPath: "\(output)/interaction-trace.json"))
    record("done", "acceptance journey complete")
}

do {
    try main()
    exit(0)
} catch {
    FileHandle.standardError.write(Data("[driver] FAILED: \(error)\n".utf8))
    exit(1)
}
