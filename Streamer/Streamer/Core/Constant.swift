public enum MontageRole:Int {
    case undefined = 0
    case cam
    case userCam
    case wizardCam
    case mirror
    case canvas
}

let logger = Logger()

enum Level {
    case info
    case warn
    case error
    case none
}

class Logger {
    var level:Level = .none
    
    func isEnabledFor(level:Level) -> Bool {
        return self.level == level
    }
    func error(_ string:String) {
        if level == .error {
            print(string)
        }
    }
    func warn(_ string:String) {
        if level == .warn {
            print(string)
        }
    }
    func info(_ string:String) {
        if level == .info {
            print(string)
        }
    }
}

public enum CMSampleBufferType: String {
    case video
    case audio
}
