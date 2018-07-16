#if os(iOS)
import UIKit
//typealias BaseClass = UIView
#else
import AppKit
//typealias BaseClass = NSView
#endif

protocol DataConvertible {
    var data: Data { get set }
}

// MARK: -
protocol Running: class {
    var running: Bool { get }
    func startRunning()
    func stopRunning()
}
