//
// ApplicationController.swift
// Apple Juice
// https://github.com/raphaelhanneken/apple-juice
//
// The MIT License (MIT)
//
// Copyright (c) 2015 Raphael Hanneken
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Cocoa

final class ApplicationController: NSObject {
  /// Holds a reference to the application menu.
  @IBOutlet weak var appMenu: NSMenu!
  /// Holds a reference to the charging status menu item.
  @IBOutlet weak var currentCharge: NSMenuItem!
  /// Holds a reference to the power source menu item.
  @IBOutlet weak var currentSource: NSMenuItem!

  /// Holds the app's status bar item.
  private var statusItem: NSStatusItem?
  /// Access to battery information.
  private var battery: Battery?
  /// Manage user preferences.
  private let userPrefs = UserPreferences()

  // MARK: - Methods

  override init() {
    // Initialize NSObject.
    super.init()
    // Configure the status bar item.
    statusItem = configureStatusItem()

    do {
      // Get access to the battery information.
      try battery = Battery()
      // Display the status bar item.
      updateStatusItem()
      // Listen for notifications.
      registerAsObserver()
    } catch {
      // Draw a status item for the catched battery error.
      batteryError(type: error as? BatteryError)
    }
  }

  ///  Gets called whenever the power source changes. Calls updateMenuItem:
  ///  and postUserNotification.
  ///  - parameter sender: Object that send the message.
  func powerSourceChanged(sender: AnyObject) {
    // Update status bar item to reflect changes.
    updateStatusItem()
    // Check if the user wants to get notified.
    postUserNotification()
  }

  ///  Displays the app menu on screen.
  ///
  ///  - parameter sender: The object that send the message.
  func displayAppMenu(sender: AnyObject) {
    // Update the information displayed within the app menu...
    updateMenuItems({
      self.statusItem?.popUpStatusItemMenu(self.appMenu)
    })
  }

  ///  Updates the status bar item every time the user defaults
  ///  change (e.g., the user chooses to display the remaining time instead of percentage).
  ///
  ///  - parameter sender: The object that send the message.
  func userDefaultsDidChange(sender: AnyObject) {
    updateStatusItem()
  }

  // MARK: - Private Methods

  ///  Creates and configures the app's status bar item.
  ///
  ///  - returns: The application's status bar item.
  private func configureStatusItem() -> NSStatusItem {
    // Find a place to life.
    let statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(NSVariableStatusItemLength)
    // Set properties.
    statusItem.target = self
    statusItem.action = #selector(ApplicationController.displayAppMenu(_:))
    return statusItem
  }

  ///  Updates the application's status bar item.
  private func updateStatusItem() {
    // Unwrap everything we need here...
    guard let button = statusItem?.button,
      timeRemaining  = battery?.timeRemainingFormatted(),
      plugged        = battery?.isPlugged(),
      charging       = battery?.isCharging(),
      charged        = battery?.isCharged(),
      percentage     = battery?.percentage() else {
        return
    }
    // ...and draw the appropriate status bar icon.
    if charged && plugged {
      button.image = StatusIcon.batteryChargedAndPlugged
    } else if charging {
      button.image = StatusIcon.batteryCharging
    } else {
      button.image = StatusIcon.batteryDischarging(currentPercentage: percentage)
    }
    // Draw the status icon on the right hand side.
    button.imagePosition = .ImageRight
    // Set the status bar item's title.
    button.attributedTitle = attributedTitle(withPercentage: percentage, andTime: timeRemaining)
    // Define the image as template.
    button.image?.template = true
  }

  ///  Updates the information within the app menu.
  ///
  ///  - parameter completionHandler: A callback function, that should get
  ///    called as soon as the menu items are updated.
  private func updateMenuItems(completionHandler: () -> Void) {
    // Unwrap the battery object.
    guard let battery = battery else {
      return
    }
    // Get the current source and set the menu item title.
    currentSource.title = "\(NSLocalizedString("source", comment: ""))"
      + " \(battery.currentSource())"
    // Display the remaining time/percentage.
    if let percentage = battery.percentage() where userPrefs.showTime {
      currentCharge.title = "\(percentage) %"
    } else {
      currentCharge.title = battery.timeRemainingFormatted()
    }
    // Display the current charge and the current capacity.
    if let charge = battery.currentCharge(), capacity = battery.maxCapacity() {
      currentCharge.title += " (\(charge) / \(capacity) mAh)"
    }
    // Run the callback.
    completionHandler()
  }

  ///  Checks if the user wants to get notified about the current charging status.
  private func postUserNotification() {
    // Unwrap the necessary information.
    guard let plugged = battery?.isPlugged(),
      charged    = battery?.isCharged(),
      percentage = battery?.percentage() else {
        return
    }
    // Define a new notification key.
    let notificationKey: NotificationKey?
    // Check what kind of notification key we have here.
    if plugged && charged {
      notificationKey = .HundredPercent
    } else if !plugged {
      notificationKey = NotificationKey(rawValue: percentage)
    } else {
      notificationKey = .None
    }
    // Unwrap the notification key and return, when we already informed the user
    // about the current percentage.
    guard let key = notificationKey where userPrefs.lastNotified != key else {
      return
    }
    // Post the notification and save it as last notified.
    if userPrefs.notifications.contains(key) {
      NotificationController.postUserNotification(forPercentage: key)
    }
    userPrefs.lastNotified = key
  }

  ///  Creates an attributed string for the status bar item's title.
  ///
  ///  - parameter percent: Current percentage of the battery's charging status.
  ///  - parameter time:    The estimated remaining time in a human readable format.
  ///  - returns: The attributed string with percentage or time information, respectively.
  private func attributedTitle(withPercentage percent: Int, andTime time: String)
    -> NSAttributedString {
      // Define some attributes to make the status bar item look like Apple's battery gauge.
      let attrs = [NSFontAttributeName : NSFont.systemFontOfSize(12.0),
        NSBaselineOffsetAttributeName : 1.0]
      // Check whether the user wants to see the remaining time or not.
      if userPrefs.showTime {
        return NSAttributedString(string: "\(time) ", attributes: attrs)
      } else {
        return NSAttributedString(string: "\(percent) % ", attributes: attrs)
      }
  }

  ///  Display a battery error.
  ///
  ///  - parameter type: The BatteryError that was thrown.
  private func batteryError(type type: BatteryError?) {
    // Unwrap the menu bar item's button.
    guard let button = statusItem?.button, type = type else {
      return
    }
    // Get the right icon and set an error message for the supplied error
    switch type {
    case .ConnectionAlreadyOpen:
      button.image = StatusIcon.batteryConnectionAlreadyOpen
    case .ServiceNotFound:
      button.image = StatusIcon.batteryServiceNotFound
    }
    // Define the image as template
    button.image?.template = true
  }

  ///  Listen for power source and user defaults notifications.
  private func registerAsObserver() {
    // Get notified, when the power source changes.
    NSNotificationCenter.defaultCenter().addObserver(self,
      selector: #selector(ApplicationController.powerSourceChanged(_:)),
          name: powerSourceChangedNotification,
        object: nil)
    // Get notified, when the user defaults change.
    NSNotificationCenter.defaultCenter().addObserver(self,
      selector: #selector(ApplicationController.userDefaultsDidChange(_:)),
          name: NSUserDefaultsDidChangeNotification,
        object: nil)
  }

  // MARK: - IBAction's

  ///  Open the energy saver preference pane.
  ///
  ///  - parameter sender: The menu item that send the message.
  @IBAction func energySaverPreferences(sender: NSMenuItem) {
    NSWorkspace.sharedWorkspace().openFile("/System/Library/PreferencePanes/EnergySaver.prefPane")
  }
}