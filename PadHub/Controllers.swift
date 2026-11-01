import GameController
import NSOGCKit
import SwiftUI

/// Turns any controller into menu commands: NSO GameCube controllers through
/// NSOGCKit (iOS has no driver for them), and every pad the system knows
/// through GameController. The menu reads their state on each screen refresh
/// rather than installing input handlers, so a game keeps its own; while a
/// game is paused behind the menu, its handlers are set aside so it does not
/// see what the player does in the menu. Main queue only.
final class Controllers: NSObject, ObservableObject, NSOGCManagerDelegate {
  enum Command { case left, right, up, down, confirm, back, menu, home }

  @Published private(set) var nsoController: NSOGCController?
  @Published private(set) var otherControllerName: String?
  @Published private(set) var bluetoothOn = true

  var onCommand: ((Command) -> Void)?

  private var started = false
  private var claimed = false
  private var displayLink: CADisplayLink?
  private var held: Set<Command> = []
  private var heldDirection: Command?
  private var repeatTimer: Timer?
  private var setAside: [(GCController, GCExtendedGamepadValueChangedHandler?)] = []

  var statusText: String {
    if let nsoController { return nsoController.name }
    if let otherControllerName { return otherControllerName }
    return bluetoothOn ? "Press SYNC on your controller" : "Bluetooth is off"
  }

  var isConnected: Bool { nsoController != nil || otherControllerName != nil }

  func start() {
    guard !started else { return }
    started = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(gameControllersChanged), name: .GCControllerDidConnect, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(gameControllersChanged), name: .GCControllerDidDisconnect,
      object: nil)
    gameControllersChanged()
    claim()
  }

  /// The menu takes the controllers: NSOGCKit reports to it, and the game
  /// behind the menu stops receiving input.
  func claim() {
    guard started, !claimed else { return }
    claimed = true
    let manager = NSOGCManager.shared
    manager.maximumControllers = 4  // anyone can drive the menu
    manager.delegate = self
    for controller in manager.controllers { controller.inputHandler = nil }
    nsoController = manager.controllers.first
    for controller in GCController.controllers() {
      guard let pad = controller.extendedGamepad else { continue }
      setAside.append((controller, pad.valueChangedHandler))
      pad.valueChangedHandler = nil
    }
    // `-PadHubNSOControllers NO` keeps Bluetooth off, so no permission prompt
    // waits on the phone during a test run from a Mac.
    let defaults = UserDefaults.standard
    if defaults.object(forKey: "PadHubNSOControllers") == nil || defaults.bool(forKey: "PadHubNSOControllers") {
      manager.start()
    }
    // A button still down from the game (HOME, say) is not a menu command.
    (held, heldDirection) = read()
    let link = CADisplayLink(target: self, selector: #selector(poll))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  /// A game comes to the front and gets its controllers back; it takes the
  /// NSO controllers itself.
  func release() {
    guard claimed else { return }
    claimed = false
    displayLink?.invalidate()
    displayLink = nil
    setDirection(nil)
    let connected = GCController.controllers()
    for (controller, handler) in setAside where connected.contains(controller) {
      controller.extendedGamepad?.valueChangedHandler = handler
    }
    setAside = []
  }

  // MARK: NSO GameCube controllers

  func manager(_ manager: NSOGCManager, didConnect controller: NSOGCController) {
    Log.write("menu: NSO controller connected \(controller.name)")
    nsoController = manager.controllers.first
    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
  }

  func manager(_ manager: NSOGCManager, didDisconnect controller: NSOGCController) {
    nsoController = manager.controllers.first { $0 !== controller }
  }

  func manager(_ manager: NSOGCManager, bluetoothAvailabilityDidChange available: Bool) {
    bluetoothOn = available
  }

  // MARK: Other controllers

  @objc private func gameControllersChanged() {
    otherControllerName = GCController.controllers().first { $0.extendedGamepad != nil }.map {
      $0.vendorName ?? "Controller"
    }
  }

  // MARK: Reading every controller once per frame

  @objc private func poll() {
    let (now, direction) = read()
    for command in [Command.confirm, .back, .menu, .home]
    where now.contains(command) && !held.contains(command) {
      onCommand?(command)
    }
    held = now
    setDirection(direction)
  }

  /// The buttons down on any controller, and the direction pushed.
  private func read() -> (Set<Command>, Command?) {
    var now: Set<Command> = []
    var stickX: Float = 0
    var stickY: Float = 0
    for controller in NSOGCManager.shared.controllers {
      let state = controller.state
      func down(_ button: nsogc_button) -> Bool { state.buttons & button.rawValue != 0 }
      if down(NSOGC_BUTTON_A) { now.insert(.confirm) }
      if down(NSOGC_BUTTON_B) { now.insert(.back) }
      if down(NSOGC_BUTTON_START) { now.insert(.menu) }
      if down(NSOGC_BUTTON_HOME) { now.insert(.home) }
      if down(NSOGC_BUTTON_DPAD_LEFT) { now.insert(.left) }
      if down(NSOGC_BUTTON_DPAD_RIGHT) { now.insert(.right) }
      if down(NSOGC_BUTTON_DPAD_UP) { now.insert(.up) }
      if down(NSOGC_BUTTON_DPAD_DOWN) { now.insert(.down) }
      if abs(state.stick_x) > abs(stickX) { stickX = state.stick_x }
      if abs(state.stick_y) > abs(stickY) { stickY = state.stick_y }
    }
    for controller in GCController.controllers() {
      guard let pad = controller.extendedGamepad else { continue }
      if pad.buttonA.isPressed { now.insert(.confirm) }
      if pad.buttonB.isPressed { now.insert(.back) }
      if pad.buttonMenu.isPressed { now.insert(.menu) }
      if pad.dpad.left.isPressed { now.insert(.left) }
      if pad.dpad.right.isPressed { now.insert(.right) }
      if pad.dpad.up.isPressed { now.insert(.up) }
      if pad.dpad.down.isPressed { now.insert(.down) }
      let x = pad.leftThumbstick.xAxis.value
      let y = pad.leftThumbstick.yAxis.value
      if abs(x) > abs(stickX) { stickX = x }
      if abs(y) > abs(stickY) { stickY = y }
    }

    var direction: Command?
    if now.contains(.left) || stickX < -0.6 {
      direction = .left
    } else if now.contains(.right) || stickX > 0.6 {
      direction = .right
    } else if now.contains(.up) || stickY > 0.6 {
      direction = .up
    } else if now.contains(.down) || stickY < -0.6 {
      direction = .down
    }
    return (now, direction)
  }

  // MARK: Held directions repeat, like a console menu

  private func setDirection(_ direction: Command?) {
    guard direction != heldDirection else { return }
    heldDirection = direction
    repeatTimer?.invalidate()
    repeatTimer = nil
    guard let direction else { return }
    onCommand?(direction)
    repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
      self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: true) { _ in
        self?.onCommand?(direction)
      }
    }
  }
}
