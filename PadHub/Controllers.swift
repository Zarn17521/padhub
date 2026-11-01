import GameController
import NSOGCKit
import SwiftUI

/// Turns any controller into menu commands: the NSO GameCube controller
/// through NSOGCKit (iOS has no driver for it), and every pad the system
/// knows through GameController. Everything runs on the main queue.
final class Controllers: NSObject, ObservableObject, NSOGCManagerDelegate {
  enum Command { case left, right, up, down, confirm, back, menu }

  @Published private(set) var nsoController: NSOGCController?
  @Published private(set) var otherControllerName: String?
  @Published private(set) var bluetoothOn = true

  var onCommand: ((Command) -> Void)?

  private var started = false
  private var nsoButtons: UInt32 = 0
  private var gcButtons: Set<String> = []
  private var heldDirection: Command?
  private var repeatTimer: Timer?

  var statusText: String {
    if let nsoController { return nsoController.name }
    if let otherControllerName { return otherControllerName }
    return bluetoothOn ? "Press SYNC on your controller" : "Bluetooth is off"
  }

  var isConnected: Bool { nsoController != nil || otherControllerName != nil }

  func start() {
    guard !started else { return }
    started = true
    let manager = NSOGCManager.shared
    manager.maximumControllers = 1
    manager.delegate = self
    manager.start()

    NotificationCenter.default.addObserver(
      self, selector: #selector(gameControllerDidConnect(_:)), name: .GCControllerDidConnect,
      object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(gameControllerDidDisconnect(_:)), name: .GCControllerDidDisconnect,
      object: nil)
    GCController.controllers().forEach(configure)
  }

  // MARK: NSO GameCube controller

  func manager(_ manager: NSOGCManager, didConnect controller: NSOGCController) {
    nsoController = controller
    nsoButtons = 0
    controller.inputHandler = { [weak self] _, state in self?.handle(state) }
    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
  }

  func manager(_ manager: NSOGCManager, didDisconnect controller: NSOGCController) {
    if nsoController === controller {
      nsoController = nil
      setDirection(nil)
    }
  }

  func manager(_ manager: NSOGCManager, bluetoothAvailabilityDidChange available: Bool) {
    bluetoothOn = available
  }

  private func handle(_ state: nsogc_state) {
    let pressed = state.buttons & ~nsoButtons
    nsoButtons = state.buttons
    func newly(_ button: nsogc_button) -> Bool { pressed & button.rawValue != 0 }
    if newly(NSOGC_BUTTON_A) { onCommand?(.confirm) }
    if newly(NSOGC_BUTTON_B) { onCommand?(.back) }
    if newly(NSOGC_BUTTON_START) { onCommand?(.menu) }

    let held = state.buttons
    var direction: Command?
    if held & NSOGC_BUTTON_DPAD_LEFT.rawValue != 0 || state.stick_x < -0.6 {
      direction = .left
    } else if held & NSOGC_BUTTON_DPAD_RIGHT.rawValue != 0 || state.stick_x > 0.6 {
      direction = .right
    } else if held & NSOGC_BUTTON_DPAD_UP.rawValue != 0 || state.stick_y > 0.6 {
      direction = .up
    } else if held & NSOGC_BUTTON_DPAD_DOWN.rawValue != 0 || state.stick_y < -0.6 {
      direction = .down
    }
    setDirection(direction)
  }

  // MARK: Other controllers

  @objc private func gameControllerDidConnect(_ notification: Notification) {
    if let controller = notification.object as? GCController { configure(controller) }
  }

  @objc private func gameControllerDidDisconnect(_ notification: Notification) {
    otherControllerName = GCController.controllers().first { $0.extendedGamepad != nil }?.vendorName
  }

  private func configure(_ controller: GCController) {
    guard let pad = controller.extendedGamepad else { return }
    otherControllerName = controller.vendorName ?? "Controller"
    pad.valueChangedHandler = { [weak self] pad, _ in self?.handle(pad) }
  }

  private func handle(_ pad: GCExtendedGamepad) {
    var held: Set<String> = []
    if pad.buttonA.isPressed { held.insert("a") }
    if pad.buttonB.isPressed { held.insert("b") }
    if pad.buttonMenu.isPressed { held.insert("menu") }
    let pressed = held.subtracting(gcButtons)
    gcButtons = held
    if pressed.contains("a") { onCommand?(.confirm) }
    if pressed.contains("b") { onCommand?(.back) }
    if pressed.contains("menu") { onCommand?(.menu) }

    let x = pad.leftThumbstick.xAxis.value
    let y = pad.leftThumbstick.yAxis.value
    var direction: Command?
    if pad.dpad.left.isPressed || x < -0.6 {
      direction = .left
    } else if pad.dpad.right.isPressed || x > 0.6 {
      direction = .right
    } else if pad.dpad.up.isPressed || y > 0.6 {
      direction = .up
    } else if pad.dpad.down.isPressed || y < -0.6 {
      direction = .down
    }
    setDirection(direction)
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
