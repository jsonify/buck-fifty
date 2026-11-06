import CloudKit
import CoreData
import Observation
import SwiftUI
import UIKit
import ShoppingCore
import ShoppingStore

/// The app's shared state: who you are, the Core Data stack and sharing. One instance, so the scene delegate can
/// accept share invitations into the same store the views use.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let profile: Profile
    let persistence: Persistence
    let sharing: SharingModel

    private init() {
        let profile = Profile()
        if Launch.isDemo { profile.name = "Jason" }
        self.profile = profile
        persistence = AppData.makePersistence(shopper: profile.shopper)
        sharing = SharingModel(service: SharingService(persistence: persistence))
        if Launch.isDemo {
            sharing.demoSummary = ShareSummary(isShared: true, isOwner: true, participants: ["Partner"])
        }
    }
}

/// Who each list is shared with, and the sharing sheet.
@MainActor
@Observable
final class SharingModel {
    @ObservationIgnored let service: SharingService
    @ObservationIgnored private var delegate: ShareDelegate?
    private var summaries: [NSManagedObjectID: ShareSummary] = [:]
    /// The demo shows every list as shared with "Partner".
    var demoSummary: ShareSummary?
    /// A sharing error to show, until dismissed.
    var errorMessage: String?
    /// While a share is being made.
    private(set) var isWorking = false

    init(service: SharingService) {
        self.service = service
    }

    func summary(for store: Store) -> ShareSummary {
        demoSummary ?? summaries[store.objectID] ?? .notShared
    }

    /// Re-reads who each store is shared with (after a remote change, or the sharing sheet).
    func refresh(_ stores: [Store]) {
        guard demoSummary == nil, service.isAvailable else { return }
        for store in stores {
            let summary = service.summary(for: store)
            if summaries[store.objectID] != summary { summaries[store.objectID] = summary }
        }
    }

    /// Shows the system sharing sheet for a store's list: invite someone (Messages, Mail, a link), or see and
    /// change who it's shared with.
    func presentSharing(for store: Store) async {
        guard let container = service.persistence.cloudKitContainer, service.isAvailable else {
            errorMessage = SharingService.SharingError.unavailable.localizedDescription
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let share = try await service.share(store)
            refresh([store])
            let controller = UICloudSharingController(share: share, container: container)
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            let delegate = ShareDelegate(title: "\(store.displayName) list") { [weak self] error in
                if let error { self?.errorMessage = error.localizedDescription }
                self?.refresh([store])
            }
            self.delegate = delegate
            controller.delegate = delegate
            Self.topViewController()?.present(controller, animated: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Accepts an invitation someone sent you; their list appears with yours.
    func accept(_ metadata: CKShare.Metadata) async {
        do {
            try await service.accept(metadata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// The sharing sheet's delegate: the list's title for the invitation, and what happened.
final class ShareDelegate: NSObject, UICloudSharingControllerDelegate {
    private let title: String
    private let changed: (Error?) -> Void

    init(title: String, changed: @escaping (Error?) -> Void) {
        self.title = title
        self.changed = changed
    }

    func itemTitle(for csc: UICloudSharingController) -> String? { title }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        changed(error)
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { changed(nil) }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { changed(nil) }
}

/// Registers for pushes (how CloudKit says something changed) and hands share invitations to `SharingModel`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Accepts a share invitation tapped in Messages or Mail, whether the app was running or not.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { accept(metadata) }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        accept(cloudKitShareMetadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        Task { @MainActor in await AppModel.shared.sharing.accept(metadata) }
    }
}
