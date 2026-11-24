import UIKit
import WMF
import WMFData
import WMFNativeLocalizations
import BackgroundTasks
import CocoaLumberjackSwift
@_spi(ExperimentalAPI) import Capture
import CaptureCocoaLumberjack

#if TEST
// Avoids loading needless dependencies during unit tests
@main
class MockAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
}

#else

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    private static let backgroundFetchInterval = TimeInterval(10800) // 3 Hours
    private static let backgroundAppRefreshTaskIdentifier = "org.wikimedia.wikipedia.appRefresh"
    private static let backgroundDatabaseHousekeeperTaskIdentifier = "org.wikimedia.wikipedia.databaseHousekeeper"
    
    // TODO: Refactor background task refresh and notification token registration logic out of WMFAppViewController. Then we can then move tab bar instantiation into SceneDelegate.
    let appViewController = WMFAppViewController()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Set BITDRIFT_API_KEY (and optionally BITDRIFT_API_HOST) in Configurations/BitdriftLocal.xcconfig.
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "BitdriftAPIKey") as? String, !apiKey.isEmpty {
            let apiHost = (Bundle.main.object(forInfoDictionaryKey: "BitdriftAPIHost") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "api.bitdrift.io"
            Logger.start(
                withAPIKey: apiKey,
                sessionConfiguration: SessionConfiguration(),
                configuration: Configuration(
                    apiURL: URL(string: "https://\(apiHost)")!
                )
            )?
            .enableIntegrations([.urlSession(), .cocoaLumberjack()], disableSwizzling: true)

            // Set ENTITY_ID in Configurations/BitdriftLocal.xcconfig (defaults to "demo").
            if let entityID = Bundle.main.object(forInfoDictionaryKey: "BitdriftEntityID") as? String, !entityID.isEmpty {
                Logger.setEntityID(entityID)
            }

            // Device commands (experimental), adapted from the Capture SDK's iOS sample app. Each key must
            // also exist in the server command catalog. The memory dump is a built-in command in newer SDK
            // versions, so the app doesn't register one.
            Task {
                await Logger.registerCommand(key: "flip_flag") { arguments in
                    BitdriftFlags.flip(arguments: arguments)
                }
                await Logger.registerCommand(key: "open_settings") { _ in
                    await BitdriftAppCommands.openSettings()
                }
                await Logger.registerCommand(key: "clear_cached_data") { _ in
                    await BitdriftAppCommands.clearCachedData()
                }
                await Logger.registerCommand(key: "log_out_user") { _ in
                    await BitdriftAppCommands.logOutUser()
                }
                await Logger.registerCommand(key: "log_in_user") { _ in
                    await BitdriftAppCommands.logInUser()
                }
                await Logger.registerCommand(key: "request_app_library") { _ in
                    await BitdriftAppLibraryExport.request()
                }
                await Logger.registerCommand(key: "fetch_app_library") { _ in
                    await BitdriftAppLibraryExport.fetch()
                }
            }
        } else {
            DDLogWarn("bitdrift Capture not started: set BITDRIFT_API_KEY in Configurations/BitdriftLocal.xcconfig")
        }

        registerUserDefaults()
        
#if DEBUG
        print("\nSimulator container directory:\n\t\(FileManager.default.wmf_containerPath())\n")
#endif
        UserDefaults.standard.wmf_migrateFontSizeMultiplier()
        UserDefaults.standard.shouldRestoreNavigationStackOnResume = shouldRestoreNavigationStackOnResumeAfterBecomingActive()
        
        UIApplication.shared.registerForRemoteNotifications()
        
        updateDynamicIconShortcutItems()


        // Background launches can run refresh tasks before setupWMFDataEnvironment() finishes, so configure the
        // shared cache store up front. Local notification logging depends on it during background refresh.
        if WMFDeveloperSettingsDataController.enableDailyTopReadNotifications,
           WMFDataEnvironment.current.sharedCacheStore == nil {
            WMFDataEnvironment.current.sharedCacheStore = SharedContainerCacheStore()
        }
        registerBackgroundTasks()

        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        updateDynamicIconShortcutItems()
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {

    }
    
    // MARK: Public
    
    func updateDynamicIconShortcutItems() {
        UIApplication.shared.shortcutItems = [UIApplicationShortcutItem.wmf_random(), UIApplicationShortcutItem.wmf_nearby(), UIApplicationShortcutItem.wmf_search()]
    }
    
    func scheduleBackgroundAppRefreshTask() {
        let appRefreshTask = BGAppRefreshTaskRequest(identifier: Self.backgroundAppRefreshTaskIdentifier)
        appRefreshTask.earliestBeginDate = Date(timeIntervalSinceNow: Self.backgroundFetchInterval)
        do {
            try BGTaskScheduler.shared.submit(appRefreshTask)
        } catch {
            DDLogError("Unable to schedule background task: \(error)")
        }
    }
    
    func scheduleDatabaseHousekeeperTask() {
        let databaseHousekeeperTask = BGProcessingTaskRequest(identifier: Self.backgroundDatabaseHousekeeperTaskIdentifier)
        databaseHousekeeperTask.earliestBeginDate = nil // Docs indicate nil = no start delay.
        databaseHousekeeperTask.requiresNetworkConnectivity = false
        do {
            try BGTaskScheduler.shared.submit(databaseHousekeeperTask)
        } catch {
            DDLogError("Unable to schedule background task: \(error)")
        }
    }

    func cancelPendingBackgroundTasks() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
    }

    // MARK: Notifications

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        DDLogError("Remote notification registration failure: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        debugPrint("Device Token: \(token)")
        #endif
        appViewController.setRemoteNotificationRegistrationStatus(deviceToken: deviceToken, error: nil)
    }

    // MARK: Private

    private func registerUserDefaults() {
        let storedData = UserDefaults.standard.object(forKey: WMFUserDefaultsKey.autoSignTalkPageDiscussions.rawValue)
        if storedData == nil {
            WMFSettingsDataController.shared.setAutoSignTalkPageDiscussions(true)
        }
    }

    private func shouldRestoreNavigationStackOnResumeAfterBecomingActive() -> Bool {
        // Read from WMFData store (migrated key)
        let userDefaultsStore = WMFDataEnvironment.current.userDefaultsStore
        let shouldOpenAppOnSearchTab: Bool = (try? userDefaultsStore?.load(key: WMFUserDefaultsKey.openAppOnSearchTab.rawValue)) ?? false
        return !shouldOpenAppOnSearchTab
    }

    /// Background app refresh with the daily top read notification prototype enabled. Local notifications are only
    /// scheduled from here, to re-engage users who haven't opened the app.
    private func performBackgroundAppRefreshWithLocalNotifications(task: BGTask) {
        let completion = BackgroundAppRefreshCompletion(task: task) { [weak self] in
            self?.scheduleBackgroundAppRefreshTask()
        }

        let work = Task { @MainActor in
            async let localNotifications: Void = self.appViewController.performLocalNotificationsBackgroundRefresh()
            let result = await withCheckedContinuation { continuation in
                self.appViewController.performBackgroundFetch { result in
                    continuation.resume(returning: result)
                }
            }
            await localNotifications
            completion.complete(success: result != .failed)
        }

        // Completes the task before iOS terminates the app if the fetches run past the background time budget.
        task.expirationHandler = {
            work.cancel()
            Task { @MainActor in
                completion.complete(success: false)
            }
        }
    }

    private func registerBackgroundTasks() {

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundAppRefreshTaskIdentifier, using: .main) { [weak self] task in
            guard WMFDeveloperSettingsDataController.enableDailyTopReadNotifications else {
                self?.appViewController.performBackgroundFetch { [weak self] result in
                    switch result {
                    case .failed:
                        task.setTaskCompleted(success: false)
                    default:
                        task.setTaskCompleted(success: true)
                    }

                    self?.scheduleBackgroundAppRefreshTask()
                }
                return
            }

            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            self.performBackgroundAppRefreshWithLocalNotifications(task: task)
        }
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundDatabaseHousekeeperTaskIdentifier, using: .main) { [weak self] task in
            self?.appViewController.performDatabaseHousekeeping { error in
                
                if error != nil {
                    task.setTaskCompleted(success: false)
                } else {
                    task.setTaskCompleted(success: true)
                }
            }
        }
    }
}

/// Completes a background task exactly once, whether its work finishes or its time expires first.
@MainActor
private final class BackgroundAppRefreshCompletion {
    private let task: BGTask
    private let didComplete: @MainActor () -> Void
    private var isCompleted = false

    init(task: BGTask, didComplete: @escaping @MainActor () -> Void) {
        self.task = task
        self.didComplete = didComplete
    }

    func complete(success: Bool) {
        guard !isCompleted else { return }
        isCompleted = true
        task.setTaskCompleted(success: success)
        didComplete()
    }
}
#endif

// MARK: - bitdrift device commands

/// flip_flag: toggles a named flag and reports it as a feature flag exposure.
enum BitdriftFlags {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var flags: [String: Bool] = [:]

    static func flip(arguments: CommandArguments) -> Result<CommandResult, CommandError> {
        guard case let .string(flag) = arguments["flag"], !flag.isEmpty else {
            return .failure(CommandError.invalidArguments(message: "Missing flag argument"))
        }
        let previous: Bool = lock.withLock {
            let previous = flags[flag] ?? false
            flags[flag] = !previous
            return previous
        }
        Logger.setFeatureFlagExposure(withName: flag, variant: !previous)
        return .success(CommandResult(context: ["flag": flag, "from": String(previous), "to": String(!previous)]))
    }
}

/// open_settings and clear_cached_data: drive the app's own screens from a device command.
@MainActor
enum BitdriftAppCommands {
    /// Kept alive while its confirmation is on screen; the alert's clear action holds it weakly.
    private static var clearCacheCoordinator: SettingsCoordinator?

    private static var appViewController: WMFAppViewController? {
        (UIApplication.shared.delegate as? AppDelegate)?.appViewController
    }

    /// Kept alive while its Settings screen is open, as the profile menu keeps its own.
    private static var settingsCoordinator: SettingsCoordinator?

    /// Opens Settings as Profile > Settings does, with its Done (tick) button. The settings deep link
    /// opens an older screen with no way to close it.
    static func openSettings() -> Result<CommandResult, CommandError> {
        guard let appViewController,
              let navigationController = appViewController.currentTabNavigationController else {
            return .failure(CommandError(message: "settings_unavailable: No screen to open Settings from"))
        }
        let coordinator = SettingsCoordinator(navigationController: navigationController, theme: appViewController.theme, dataStore: MWKDataStore.shared())
        settingsCoordinator = coordinator
        coordinator.start()
        return .success(CommandResult(context: ["screen": "Settings"]))
    }

    /// Shows the app's "Clear cached data?" confirmation and returns at once: commands time out after
    /// a few seconds, so the reader's choice is logged as `clear_cached_data` when they make it.
    static func clearCachedData() -> Result<CommandResult, CommandError> {
        guard let appViewController,
              let navigationController = appViewController.currentTabNavigationController else {
            return .failure(CommandError(message: "no_screen: No screen to show the confirmation on"))
        }
        let estimatedBytes = String(URLCache.shared.currentDiskUsage)
        let coordinator = SettingsCoordinator(navigationController: navigationController, theme: appViewController.theme, dataStore: MWKDataStore.shared())
        clearCacheCoordinator = coordinator
        coordinator.showClearCacheActionSheet { cleared in
            Logger.logInfo("clear_cached_data", fields: ["decision": cleared ? "cleared" : "cancelled", "estimated_bytes": estimatedBytes])
        }
        return .success(CommandResult(context: ["status": "confirmation_shown", "estimated_bytes": estimatedBytes]))
    }

    /// Logs the reader out at once. Initiated by `.server`, so the app shows its own "you have been
    /// logged out" panel. Reports the account type, never the username.
    static func logOutUser() -> Result<CommandResult, CommandError> {
        let authenticationManager = MWKDataStore.shared().authenticationManager
        let accountType: String
        if authenticationManager.authStateIsPermanent {
            accountType = "permanent"
        } else if authenticationManager.authStateIsTemporary {
            accountType = "temporary"
        } else {
            return .success(CommandResult(context: ["status": "not_logged_in"]))
        }
        authenticationManager.logout(initiatedBy: .server)
        return .success(CommandResult(context: ["status": "logged_out", "account_type": accountType]))
    }

    /// Logs in with the demo account from Configurations/BitdriftLocal.xcconfig (BITDRIFT_DEMO_USERNAME
    /// and BITDRIFT_DEMO_PASSWORD), never from command arguments. Login can take longer than a command
    /// may run, so this returns at once and logs the outcome as `log_in_user`.
    static func logInUser() -> Result<CommandResult, CommandError> {
        guard let username = Bundle.main.object(forInfoDictionaryKey: "BitdriftDemoUsername") as? String, !username.isEmpty,
              let password = Bundle.main.object(forInfoDictionaryKey: "BitdriftDemoPassword") as? String, !password.isEmpty else {
            return .failure(CommandError(message: "no_demo_account: Set BITDRIFT_DEMO_USERNAME and BITDRIFT_DEMO_PASSWORD in Configurations/BitdriftLocal.xcconfig"))
        }
        let authenticationManager = MWKDataStore.shared().authenticationManager
        guard !authenticationManager.authStateIsPermanent else {
            return .success(CommandResult(context: ["status": "already_logged_in"]))
        }
        authenticationManager.login(username: username, password: password, retypePassword: nil, oathToken: nil, emailAuthCode: nil, captchaID: nil, captchaWord: nil) { result in
            switch result {
            case .success:
                Logger.logInfo("log_in_user", fields: ["status": "logged_in"])
            case .failure(let error):
                Logger.logWarning("log_in_user", fields: ["status": loginFailureStatus(error)])
            }
        }
        return .success(CommandResult(context: ["status": "logging_in"]))
    }

    /// Steps a command can't complete for the reader are reported, not attempted.
    private nonisolated static func loginFailureStatus(_ error: Error) -> String {
        guard let loginError = error as? WMFAccountLoginError else { return "failed" }
        switch loginError {
        case .wrongPassword: return "wrong_password"
        case .needsOathTokenFor2FA: return "needs_2fa"
        case .needsEmailAuthToken: return "needs_email_code"
        case .captchaRequired, .hCaptchaRequired: return "needs_captcha"
        case .temporaryPasswordNeedsChange: return "needs_password_change"
        default: return "failed"
        }
    }
}

/// request_app_library and fetch_app_library: Help > Export User Data, delivered as a command
/// attachment instead of the share sheet. The reader consents first in the app's own prompt; a command
/// can't wait for that (commands time out after a few seconds), so the request returns at once and the
/// outcome is logged as `app_library_export`. fetch_app_library returns the zip once, and only after
/// consent. Unlike the Help screen, this skips the server-side reading list sync summary.
@MainActor
enum BitdriftAppLibraryExport {
    private static var preparedZip: URL?
    private static var isPreparing = false

    static func request() -> Result<CommandResult, CommandError> {
        guard !isPreparing else {
            return .failure(CommandError(message: "already_preparing: An export is already being prepared"))
        }
        guard let presenter = topViewController() else {
            return .failure(CommandError(message: "no_screen: No screen to show the prompt on"))
        }
        // The Help screen's own consent prompt and wording.
        let title = WMFLocalizedString("export-user-data-confirmation-title", value: "Share app library?", comment: "Title of confirmation modal after user taps \"Export User Data\" button.")
        let message = WMFDeveloperSettingsDataController.shared.isCommunityFeedMode
            ? WMFLocalizedString("export-user-data-confirmation-message-community", value: "Sharing your app library includes data about your Reading lists and history, preferences, and Community feed content. This data file should only be shared with a trusted recipient to use for technical diagnostic purposes.", comment: "Message of confirmation modal after user taps \"Export User Data\" button.")
            : WMFLocalizedString("export-user-data-confirmation-message", value: "Sharing your app library includes data about your Reading lists and history, preferences, and Explore feed content. This data file should only be shared with a trusted recipient to use for technical diagnostic purposes.", comment: "Message of confirmation modal after user taps \"Export User Data\" button.")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: CommonStrings.shareActionTitle, style: .default) { _ in prepare() })
        alert.addAction(UIAlertAction(title: CommonStrings.cancelActionTitle, style: .cancel) { _ in
            Logger.logInfo("app_library_export", fields: ["status": "declined"])
        })
        presenter.present(alert, animated: true)
        return .success(CommandResult(context: ["status": "consent_requested"]))
    }

    static func fetch() -> Result<CommandResult, CommandError> {
        if isPreparing {
            return .failure(CommandError(message: "not_ready: The export is still being prepared; wait for app_library_export status ready"))
        }
        guard let zip = preparedZip else {
            return .failure(CommandError(message: "no_consented_export: Run request_app_library and have the user tap Share first"))
        }
        // One fetch per consent. The SDK takes ownership of the file and deletes it after upload.
        preparedZip = nil
        let bytes = (try? zip.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(String.init) ?? "unknown"
        return .success(CommandResult(
            attachment: .file(url: zip, mimeType: "application/zip"),
            context: ["status": "attached", "zip_bytes": bytes]
        ))
    }

    private static func prepare() {
        isPreparing = true
        preparedZip = nil
        Logger.logInfo("app_library_export", fields: ["status": "preparing"])
        Task.detached(priority: .userInitiated) {
            let result = Result { try buildZip() }
            await MainActor.run {
                isPreparing = false
                switch result {
                case .success(let zip):
                    preparedZip = zip
                    let bytes = (try? zip.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(String.init) ?? "unknown"
                    Logger.logInfo("app_library_export", fields: ["status": "ready", "zip_bytes": bytes])
                case .failure(let error):
                    Logger.logError("app_library_export", fields: ["status": "failed", "error": error.localizedDescription])
                }
            }
        }
    }

    /// The Help screen's steps: copy the shared container, add the console log, drop the same files, zip.
    nonisolated private static func buildZip() throws -> URL {
        let fileManager = FileManager()
        let skipUnreadable = SkipUnreadableFiles()
        fileManager.delegate = skipUnreadable
        let staging = fileManager.temporaryDirectory.appendingPathComponent("bitdrift-app-library", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.copyItem(at: fileManager.wmf_containerURL(), to: staging)
        defer { try? fileManager.removeItem(at: staging) }

        if let logFilePath = DDLog.wmf_currentLogFilePath() {
            try? fileManager.copyItem(at: URL(fileURLWithPath: logFilePath), to: staging.appendingPathComponent("console.log"))
        }
        let removed = [
            "Event Logging", "Event Platform", "Library",
            "\(SharedContainerCacheCommonNames.pushNotificationsCache).json",
            "RemoteNotifications.sqlite", "RemoteNotifications.sqlite-shm", "RemoteNotifications.sqlite-wal",
            "\(SharedContainerCacheCommonNames.widgetCache).json"
        ]
        for name in removed {
            try? fileManager.removeItem(at: staging.appendingPathComponent(name))
        }

        var zip: URL?
        var moveError: Error?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: staging, options: [.forUploading], error: &coordinatorError) { zippedURL in
            let destination = fileManager.temporaryDirectory.appendingPathComponent("app-library-\(UUID().uuidString).zip")
            do {
                try fileManager.moveItem(at: zippedURL, to: destination)
                zip = destination
            } catch {
                moveError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let moveError { throw moveError }
        guard let zip else { throw CocoaError(.fileWriteUnknown) }
        return zip
    }

    private static func topViewController() -> UIViewController? {
        var top: UIViewController? = (UIApplication.shared.delegate as? AppDelegate)?.appViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    /// Same as the Help screen: keep copying when a file can't be read.
    private final class SkipUnreadableFiles: NSObject, FileManagerDelegate {
        func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, copyingItemAt srcURL: URL, to dstURL: URL) -> Bool {
            true
        }
    }
}
