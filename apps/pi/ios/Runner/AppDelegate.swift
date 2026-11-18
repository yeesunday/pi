import CloudKit
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()

    let cloudChannel = FlutterMethodChannel(name: "dev.buildpi.piApp/cloud_sync", binaryMessenger: messenger)
    cloudChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        CKContainer.default().accountStatus { status, error in
          DispatchQueue.main.async {
            if let error {
              result(FlutterError(code: "icloud-account", message: error.localizedDescription, details: nil))
            } else {
              result(status == .available)
            }
          }
        }
      case "synchronize":
        guard let arguments = call.arguments as? [String: Any],
              let changes = arguments["changes"] as? [String] else {
          result(FlutterError(code: "bad-arguments", message: "缺少同步数据", details: nil))
          return
        }
        Task {
          do {
            let response = try await PiCloudStore.shared.synchronize(changes: changes)
            await MainActor.run { result(response) }
          } catch {
            await MainActor.run {
              result(FlutterError(code: "cloudkit", message: error.localizedDescription, details: nil))
            }
          }
        }
      case "acknowledgeRemote":
        guard let arguments = call.arguments as? [String: Any],
              let ids = arguments["ids"] as? [String] else {
          result(FlutterError(code: "bad-arguments", message: "缺少远端确认标识", details: nil))
          return
        }
        Task {
          await PiCloudStore.shared.acknowledgeRemote(ids: ids)
          await MainActor.run { result(nil) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let notificationChannel = FlutterMethodChannel(name: "dev.buildpi.piApp/notifications", binaryMessenger: messenger)
    notificationChannel.setMethodCallHandler { call, result in
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "replaceWindow":
        guard let arguments = call.arguments as? [String: Any],
              let requests = arguments["requests"] as? [[String: Any]] else {
          result(FlutterError(code: "bad-arguments", message: "提醒参数不完整", details: nil))
          return
        }
        self.replaceNotificationWindow(requests, center: center) { error in
          DispatchQueue.main.async {
            if let error {
              result(FlutterError(code: "notifications", message: error.localizedDescription, details: nil))
            } else {
              result(nil)
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func replaceNotificationWindow(
    _ definitions: [[String: Any]],
    center: UNUserNotificationCenter,
    completion: @escaping (Error?) -> Void
  ) {
    guard !definitions.isEmpty else {
      center.removeAllPendingNotificationRequests()
      completion(nil)
      return
    }

    func install() {
      center.removeAllPendingNotificationRequests()
      let group = DispatchGroup()
      let lock = NSLock()
      var firstError: Error?
      for definition in definitions.prefix(60) {
        guard let request = self.notificationRequest(definition) else { continue }
        group.enter()
        center.add(request) { error in
          if let error {
            lock.lock()
            if firstError == nil { firstError = error }
            lock.unlock()
          }
          group.leave()
        }
      }
      group.notify(queue: .main) { completion(firstError) }
    }

    center.getNotificationSettings { settings in
      if settings.authorizationStatus == .notDetermined {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
          if let error { completion(error) }
          else if granted { install() }
          else { completion(nil) }
        }
      } else if settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional ||
                  settings.authorizationStatus == .ephemeral {
        install()
      } else {
        completion(nil)
      }
    }
  }

  private func notificationRequest(_ definition: [String: Any]) -> UNNotificationRequest? {
    guard let id = definition["id"] as? String,
          let title = definition["title"] as? String,
          let milliseconds = definition["timestamp"] as? NSNumber else { return nil }
    let content = UNMutableNotificationContent()
    let sourceName = definition["sourceName"] as? String ?? "提醒"
    content.title = "Pi · \(sourceName)"
    content.body = title
    if definition["sound"] as? Bool != false { content.sound = .default }

    let date = Date(timeIntervalSince1970: milliseconds.doubleValue / 1000)
    let repeatUnit = definition["repeat"] as? String ?? "none"
    let repeated = repeatUnit != "none"
    let componentSet: Set<Calendar.Component>
    switch repeatUnit {
    case "day": componentSet = [.hour, .minute]
    case "week": componentSet = [.weekday, .hour, .minute]
    case "month": componentSet = [.day, .hour, .minute]
    case "year": componentSet = [.month, .day, .hour, .minute]
    default: componentSet = [.year, .month, .day, .hour, .minute]
    }
    var calendar = Calendar(identifier: .gregorian)
    if let timezone = definition["timezone"] as? String,
       let selected = TimeZone(identifier: timezone) {
      calendar.timeZone = selected
    }
    var components = calendar.dateComponents(componentSet, from: date)
    components.timeZone = calendar.timeZone
    return UNNotificationRequest(
      identifier: id,
      content: content,
      trigger: UNCalendarNotificationTrigger(
        dateMatching: components,
        repeats: repeated
      )
    )
  }
}

private final actor PiCloudStore: CKSyncEngineDelegate {
  static let shared = PiCloudStore()
  private static let zoneName = "PiEntities"
  private static let recordType = "PiEntity"
  private static let stateKey = "pi.cloud.syncEngineState"
  private static let bridgeKey = "pi.cloud.bridgeState"

  private let database = CKContainer.default().privateCloudDatabase
  private var engineStorage: CKSyncEngine?
  private var pendingPayloads: [String: String] = [:]
  private var pendingRemote: [String: String] = [:]
  private var recordSystemFields: [String: Data] = [:]
  private var acknowledged: [String: Int] = [:]
  private var conflictCount = 0

  private var zoneID: CKRecordZone.ID {
    CKRecordZone.ID(zoneName: Self.zoneName)
  }

  private var syncEngine: CKSyncEngine {
    if let engineStorage { return engineStorage }
    let serialization = UserDefaults.standard.data(forKey: Self.stateKey)
      .flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
    var configuration = CKSyncEngine.Configuration(
      database: database,
      stateSerialization: serialization,
      delegate: self
    )
    // Pi intentionally syncs only after a user action or the app's daily run.
    configuration.automaticallySync = false
    let engine = CKSyncEngine(configuration)
    engineStorage = engine
    restoreBridgeState()
    return engine
  }

  func synchronize(changes: [String]) async throws -> [String: Any] {
    acknowledged = [:]
    conflictCount = 0
    let engine = syncEngine
    var pending = [CKSyncEngine.PendingRecordZoneChange]()
    for payload in changes {
      guard let data = payload.data(using: .utf8),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? String else {
        throw PiCloudError.invalidPayload
      }
      pendingPayloads[id] = payload
      pending.append(.saveRecord(CKRecord.ID(recordName: id, zoneID: zoneID)))
    }
    engine.state.add(
      pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))]
    )
    engine.state.add(pendingRecordZoneChanges: pending)
    persistBridgeState()
    try await engine.sendChanges()
    try await engine.fetchChanges()
    let remote = pendingRemote.values.compactMap { value in
      try? JSONSerialization.jsonObject(with: Data(value.utf8))
    }
    let remoteData = try JSONSerialization.data(withJSONObject: remote)
    return [
      "payload": String(data: remoteData, encoding: .utf8) ?? "[]",
      "acknowledged": acknowledged,
      "conflicts": conflictCount,
    ]
  }

  func acknowledgeRemote(ids: [String]) {
    for id in ids { pendingRemote[id] = nil }
    persistBridgeState()
  }

  func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    switch event {
    case .stateUpdate(let event):
      if let data = try? JSONEncoder().encode(event.stateSerialization) {
        UserDefaults.standard.set(data, forKey: Self.stateKey)
      }
    case .fetchedRecordZoneChanges(let event):
      for modification in event.modifications {
        remember(modification.record)
        if let payload = modification.record["payload"] as? String {
          pendingRemote[modification.record.recordID.recordName] = payload
        }
      }
      persistBridgeState()
    case .sentRecordZoneChanges(let event):
      handleSentRecordZoneChanges(event, syncEngine: syncEngine)
    case .accountChange(let event):
      switch event.changeType {
      case .switchAccounts(_, _), .signOut(_):
        pendingRemote = [:]
        recordSystemFields = [:]
        UserDefaults.standard.removeObject(forKey: Self.stateKey)
        engineStorage = nil
        persistBridgeState()
      case .signIn(_):
        break
      @unknown default:
        break
      }
    case .fetchedDatabaseChanges,
         .sentDatabaseChanges,
         .willFetchChanges,
         .willFetchRecordZoneChanges,
         .didFetchRecordZoneChanges,
         .didFetchChanges,
         .willSendChanges,
         .didSendChanges:
      break
    @unknown default:
      break
    }
  }

  func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    let changes = syncEngine.state.pendingRecordZoneChanges.filter {
      context.options.scope.contains($0)
    }
    let payloads = pendingPayloads
    let systemFields = recordSystemFields
    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
      guard let payload = payloads[recordID.recordName] else {
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        return nil
      }
      let record = Self.decodeRecord(systemFields[recordID.recordName]) ??
        CKRecord(recordType: Self.recordType, recordID: recordID)
      record["payload"] = payload as CKRecordValue
      return record
    }
  }

  private func handleSentRecordZoneChanges(
    _ event: CKSyncEngine.Event.SentRecordZoneChanges,
    syncEngine: CKSyncEngine
  ) {
    for record in event.savedRecords {
      let id = record.recordID.recordName
      remember(record)
      if let payload = pendingPayloads[id],
         let revision = Self.revision(in: payload) {
        acknowledged[id] = revision
      }
      pendingPayloads[id] = nil
    }

    var databaseChanges = [CKSyncEngine.PendingDatabaseChange]()
    var recordChanges = [CKSyncEngine.PendingRecordZoneChange]()
    for failed in event.failedRecordSaves {
      let id = failed.record.recordID.recordName
      switch failed.error.code {
      case .serverRecordChanged:
        if let server = failed.error.serverRecord {
          remember(server)
          if let payload = server["payload"] as? String {
            pendingRemote[id] = payload
          }
        }
        pendingPayloads[id] = nil
        syncEngine.state.remove(
          pendingRecordZoneChanges: [.saveRecord(failed.record.recordID)]
        )
        conflictCount += 1
      case .zoneNotFound:
        recordSystemFields[id] = nil
        databaseChanges.append(.saveZone(CKRecordZone(zoneID: zoneID)))
        recordChanges.append(.saveRecord(failed.record.recordID))
      case .unknownItem:
        recordSystemFields[id] = nil
        recordChanges.append(.saveRecord(failed.record.recordID))
      default:
        break
      }
    }
    syncEngine.state.add(pendingDatabaseChanges: databaseChanges)
    syncEngine.state.add(pendingRecordZoneChanges: recordChanges)
    persistBridgeState()
  }

  private func remember(_ record: CKRecord) {
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: archiver)
    recordSystemFields[record.recordID.recordName] = archiver.encodedData
  }

  private static func decodeRecord(_ data: Data?) -> CKRecord? {
    guard let data else { return nil }
    do {
      let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
      unarchiver.requiresSecureCoding = true
      return CKRecord(coder: unarchiver)
    } catch {
      return nil
    }
  }

  private static func revision(in payload: String) -> Int? {
    guard let data = payload.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return (object["revision"] as? NSNumber)?.intValue
  }

  private func restoreBridgeState() {
    guard pendingPayloads.isEmpty,
          pendingRemote.isEmpty,
          recordSystemFields.isEmpty,
          let object = UserDefaults.standard.dictionary(forKey: Self.bridgeKey)
    else { return }
    pendingPayloads = object["pendingPayloads"] as? [String: String] ?? [:]
    pendingRemote = object["pendingRemote"] as? [String: String] ?? [:]
    if let encoded = object["recordSystemFields"] as? [String: String] {
      recordSystemFields = encoded.compactMapValues { Data(base64Encoded: $0) }
    }
  }

  private func persistBridgeState() {
    UserDefaults.standard.set([
      "pendingPayloads": pendingPayloads,
      "pendingRemote": pendingRemote,
      "recordSystemFields": recordSystemFields.mapValues { $0.base64EncodedString() },
    ], forKey: Self.bridgeKey)
  }
}

private enum PiCloudError: LocalizedError {
  case invalidPayload
  var errorDescription: String? { "iCloud 同步数据格式无效" }
}
