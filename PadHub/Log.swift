import Foundation

/// PadHub's own log, Documents/PadHub.log (the Files app shows it). Each game
/// keeps its own in Library/Application Support/<game>/Logs.
enum Log {
  private static let queue = DispatchQueue(label: "padhub.log", qos: .utility)
  private static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("PadHub.log")

  static func write(_ message: String) {
    let line = "\(Date().ISO8601Format()) \(message)\n"
    queue.async {
      guard let handle = try? FileHandle(forWritingTo: url) else {
        try? Data(line.utf8).write(to: url)
        return
      }
      // One launch's worth is plenty: start over past a megabyte.
      if let size = try? handle.seekToEnd(), size > 1_000_000 {
        try? handle.truncate(atOffset: 0)
      }
      try? handle.write(contentsOf: Data(line.utf8))
      try? handle.close()
    }
  }
}
