//
//  Copyright © 2018 Gnosis Ltd. All rights reserved.
//

import UIKit
import MultisigWalletApplication
import IdentityAccessApplication
import Common
import UserNotifications

open class MainFlowCoordinator: FlowCoordinator {

    public static let shared = MainFlowCoordinator()

    private let manageTokensFlowCoordinator = ManageTokensFlowCoordinator()
    let masterPasswordFlowCoordinator = MasterPasswordFlowCoordinator()
    let sendFlowCoordinator = SendFlowCoordinator()
    let newSafeFlowCoordinator = CreateSafeFlowCoordinator()
    let recoverSafeFlowCoordinator = RecoverSafeFlowCoordinator()
    let incomingTransactionsManager = IncomingTransactionsManager()
    let walletConnectFlowCoordinator = WalletConnectFlowCoordinator()
    let addressBookFlowCoordinator = AddressBookFlowCoordinator()
    let contractUpgradeFlowCoordinator = ContractUpgradeFlowCoordinator()
    /// Used for modal transitioning of Terms screen
    private lazy var overlayAnimatorFactory = OverlayAnimatorFactory()

    public var crashlytics: CrashlyticsProtocol?

    private var lockedViewController: UIViewController!

    private let transactionSubmissionHandler = TransactionSubmissionHandler()

    private var applicationRootViewController: UIViewController? {
        get { return UIApplication.shared.keyWindow?.rootViewController }
        set { UIApplication.shared.keyWindow?.rootViewController = newValue }
    }

    // TODO: GH-1181: re-implement this with a "childFlowCoordinator" idea
    // or a global root view controller.
    // The idea here is that when root controller changes, all of the flow coordinators
    // should change the root.
    override func setRoot(_ controller: UIViewController) {
        guard rootViewController !== controller else { return }
        super.setRoot(controller)
        [manageTokensFlowCoordinator,
         masterPasswordFlowCoordinator,
         sendFlowCoordinator,
         newSafeFlowCoordinator,
         recoverSafeFlowCoordinator,
         walletConnectFlowCoordinator,
         addressBookFlowCoordinator,
         contractUpgradeFlowCoordinator].forEach { $0.setRoot(controller) }
    }

    public init() {
        super.init(rootViewController: CustomNavigationController())
        configureGloabalAppearance()
    }

    private func configureGloabalAppearance() {
        UIButton.appearance().tintColor = ColorName.hold.color
        UIBarButtonItem.appearance().tintColor = ColorName.hold.color
        UIButton.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).tintColor = nil

        let navBarAppearance = UINavigationBar.appearance()
        navBarAppearance.barTintColor = ColorName.snowwhite.color
        navBarAppearance.tintColor = ColorName.hold.color
        navBarAppearance.isTranslucent = false
        navBarAppearance.setBackgroundImage(UIImage(), for: .default)
        navBarAppearance.shadowImage = Asset.shadow.image
    }

    // Entry point to the app
    open override func setUp() {
        super.setUp()
        appDidFinishLaunching()
    }

    func appDidFinishLaunching() {
        updateUserIdentifier()

        ApplicationServiceRegistry.walletService.cleanUpDrafts()
        ApplicationServiceRegistry.walletService.repairModelIfNeeded()
        ApplicationServiceRegistry.walletService.resumeDeploymentInBackground()
        ApplicationServiceRegistry.recoveryService.resumeRecoveryInBackground()

        defer {
            ApplicationServiceRegistry.walletConnectService.subscribeForIncomingTransactions(self)
        }
        if !ApplicationServiceRegistry.authenticationService.isUserRegistered {
            push(OnboardingWelcomeViewController.create(delegate: self))
            applicationRootViewController = rootViewController
            return
        } else {
            switchToRootController()
        }
        requestToUnlockApp()
    }

    private func updateUserIdentifier() {
        guard let crashlytics = crashlytics,
            let wallet = ApplicationServiceRegistry.walletService.selectedWalletAddress else { return }
        crashlytics.setUserIdentifier(wallet)
    }

    func switchToRootController() {
        updateUserIdentifier()
        if ApplicationServiceRegistry.walletService.hasReadyToUseWallet {
            DispatchQueue.main.async { [unowned self] in
                self.registerForRemoteNotifciations()
            }

            if let existingVC = navigationController.topViewController as? MainViewController,
                existingVC.walletID == ApplicationServiceRegistry.walletService.selectedWalletID() {
                return
            }

            let mainVC = MainViewController.create(delegate: self)
            mainVC.navigationItem.backBarButtonItem = .backButton()
            setRoot(CustomNavigationController(rootViewController: mainVC))
        } else if ApplicationServiceRegistry.walletService.isSafeCreationInProgress {
            didSelectNewSafe()
        } else if ApplicationServiceRegistry.recoveryService.isRecoveryInProgress() {
            didSelectRecoverSafe()
        } else if !(navigationController.topViewController is OnboardingCreateOrRestoreViewController) {
            let vc = OnboardingCreateOrRestoreViewController.create(delegate: self)
            setRoot(CustomNavigationController(rootViewController: vc))
        }
    }

    func requestToUnlockApp(useUIApplicationRoot: Bool = false) {
        // TODO: try to use local `lockedViewController` since it will be captured by the UnlockVC's closure.
        lockedViewController = useUIApplicationRoot ? applicationRootViewController : rootViewController
        applicationRootViewController = UnlockViewController.create { [unowned self] success in
            if !success { return }
            self.applicationRootViewController = self.lockedViewController
            self.lockedViewController = nil
        }
    }

    open func appEntersForeground() {
        if ApplicationServiceRegistry.authenticationService.isUserRegistered &&
            !ApplicationServiceRegistry.authenticationService.isUserAuthenticated &&
            !(applicationRootViewController is UnlockViewController) {
            requestToUnlockApp(useUIApplicationRoot: true)
        }
    }

    // iOS: for unknown reason, when alert or activity controller was presented and we
    // set the UIWindow's root to the root controller that presented that alert,
    // then all the views (and controllers) under the presented alert are removed when the app
    // enters foreground.
    // Dismissing such alerts and controllers after minimizing the app helps.
    open func appEnteredBackground() {
        if let presentedVC = applicationRootViewController?.presentedViewController,
            presentedVC is UIAlertController || presentedVC is UIActivityViewController {
            presentedVC.dismiss(animated: false, completion: nil)
        }
    }

    open func receive(message: [AnyHashable: Any]) {
        DispatchQueue.global.async { [unowned self] in
            do {
                guard let transactionID = try ApplicationServiceRegistry.walletService.receive(message: message),
                    let tx = ApplicationServiceRegistry.walletService.transactionData(transactionID) else { return }
                DispatchQueue.main.async {
                    if let vc = self.navigationController.topViewController as? ReviewTransactionViewController,
                        tx.id == vc.tx.id {
                        vc.update(with: tx)
                    } else if tx.status != .rejected {
                        self.handleIncomingPushTransaction(transactionID)
                    }
                }
            } catch WalletApplicationServiceError.validationFailed { // dangerous transaction
                DispatchQueue.main.async {
                    let vc = self.navigationController.topViewController
                    vc?.present(UIAlertController.dangerousTransaction(), animated: true, completion: nil)
                }
            } catch {
                MultisigWalletApplication.ApplicationServiceRegistry.logger.error("Unexpected receive message error",
                                                                                  error: error)
            }
        }
    }

    private func handleIncomingPushTransaction(_ transactionID: String) {
        let coordinator = incomingTransactionsManager.coordinator(for: transactionID, source: .browserExtension)
        // it is important not to use the coordinator inside the flow completion, because it creates retain cycle.
        let transactionID = coordinator.transactionID
        enterTransactionFlow(coordinator, transactionID: transactionID) { [unowned self] in
            self.incomingTransactionsManager.releaseCoordinator(by: transactionID)
        }
    }

    private func handleIncomingWalletConnectTransaction(_ transaction: WCPendingTransaction) {
        let rejectHandler: () -> Void = {
            let rejectedError = NSError(domain: "io.gnosis.safe",
                                        code: -401,
                                        userInfo: [NSLocalizedDescriptionKey: "Rejected by user"])
            transaction.completion(.failure(rejectedError))
        }
        let coordinator = incomingTransactionsManager.coordinator(for: transaction.transactionID.id,
                                                                  source: .walletConnect,
                                                                  sourceMeta: transaction.sessionData,
                                                                  onBack: rejectHandler)
        // it is important not to use the coordinator inside the flow completion, because it creates retain cycle.
        let transactionID = coordinator.transactionID
        enterTransactionFlow(coordinator, transactionID: transactionID) { [unowned self] in
            self.incomingTransactionsManager.releaseCoordinator(by: transactionID)
            let hash = ApplicationServiceRegistry.walletService.transactionHash(transaction.transactionID) ?? "0x"
            transaction.completion(.success(hash))
        }
    }

    // Used for incoming transaction and send flow
    fileprivate func enterTransactionFlow(_ flow: FlowCoordinator,
                                          transactionID: String? = nil,
                                          completion: (() -> Void)? = nil) {
        dismissModal()
        saveCheckpoint()
        enter(flow: flow) { [unowned self] in
            DispatchQueue.main.async {
                self.popToLastCheckpoint()

                // if the transaction belongs to a different wallet than selected one, then it won't be shown
                // in the transaction list. Thus, we should skip opening the list in that case.
                if let id = transactionID,
                    let transaction = ApplicationServiceRegistry.walletService.transactionData(id),
                    let selectedWalletID = ApplicationServiceRegistry.walletService.selectedWalletID(),
                    transaction.walletID != selectedWalletID {
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                    self.showTransactionList()
                }
            }
            completion?()
        }
    }

    internal func showTransactionList() {
        if let mainVC = self.navigationController.topViewController as? MainViewController {
            mainVC.showTransactionList()
        }
    }

    func registerForRemoteNotifciations() {
        // notification registration must be on the main thread
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        UIApplication.shared.registerForRemoteNotifications()
        // We need to update push token information with all related app info (client, version, build)
        // on every app start.
        if let token = ApplicationServiceRegistry.walletService.pushToken() {
            updatePushToken(token)
        }
    }

    public func updatePushToken(_ token: String) {
        DispatchQueue.global.async {
            try? ApplicationServiceRegistry.walletService.auth(pushToken: token)
        }
    }

    open func receive(url: URL) {
        guard walletConnectFlowCoordinator.canHandle(url) else { return }
        walletConnectFlowCoordinator.connectionURL = url
        self.enter(flow: walletConnectFlowCoordinator)
    }

}

// MARK: - EventSubscriber

extension MainFlowCoordinator: EventSubscriber {

    // SendTransactionRequested
    public func notify() {
        DispatchQueue.main.async {
            ApplicationServiceRegistry.walletConnectService.popPendingTransactions().forEach {
                self.handleIncomingWalletConnectTransaction($0)
            }
        }
    }

}

// MARK: - OnboardingWelcomeViewControllerDelegate

extension MainFlowCoordinator: OnboardingWelcomeViewControllerDelegate {

    func didStart() {
        let controller = OnboardingTermsViewController.create()
        controller.delegate = self
        controller.modalPresentationStyle = .custom
        controller.transitioningDelegate = overlayAnimatorFactory
        rootViewController.definesPresentationContext = true
        presentModally(controller)
    }

}

// MARK: - OnboardingTermsViewControllerDelegate

extension MainFlowCoordinator: OnboardingTermsViewControllerDelegate {

    public func wantsToOpenTermsOfUse() {
        SupportFlowCoordinator(from: self).openTermsOfUse()
    }

    public func wantsToOpenPrivacyPolicy() {
        SupportFlowCoordinator(from: self).openPrivacyPolicy()
    }

    public func didDisagree() {
        dismissModal()
    }

    public func didAgree() {
        dismissModal { [unowned self] in
            self.enter(flow: self.masterPasswordFlowCoordinator) {
                self.switchToRootController()
            }
        }
    }

}

// MARK: - OnboardingCreateOrRestoreViewControllerDelegate

extension MainFlowCoordinator: OnboardingCreateOrRestoreViewControllerDelegate {

    func didSelectNewSafe() {
        enter(flow: newSafeFlowCoordinator)
    }

    func didSelectRecoverSafe() {
        enter(flow: recoverSafeFlowCoordinator)
    }

}

// MARK: - MainViewControllerDelegate

extension MainFlowCoordinator: MainViewControllerDelegate {

    func createNewTransaction(token: String, address: String?) {
        sendFlowCoordinator.token = token
        sendFlowCoordinator.address = address
        enterTransactionFlow(sendFlowCoordinator)
    }

    func openMenu() {
        let menuVC = MenuTableViewController.create()
        menuVC.delegate = self
        push(menuVC)
    }

    func manageTokens() {
        enter(flow: manageTokensFlowCoordinator)
    }

    func openAddressDetails() {
        let addressDetailsVC = ReceiveFundsViewController.create()
        push(addressDetailsVC)
    }

    func upgradeContract() {
        saveCheckpoint()
        enter(flow: contractUpgradeFlowCoordinator) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let `self` = self else { return }
                self.popToLastCheckpoint()
                self.showTransactionList()
            }
        }
    }

}

// MARK: - TransactionViewViewControllerDelegate

extension MainFlowCoordinator: TransactionViewViewControllerDelegate {

    public func didSelectTransaction(id: String) {
        let controller = TransactionDetailsViewController.create(transactionID: id)
        controller.delegate = self
        push(controller)
    }

}

// MARK: - TransactionDetailsViewControllerDelegate

extension MainFlowCoordinator: TransactionDetailsViewControllerDelegate {

    public func showTransactionInExternalApp(from controller: TransactionDetailsViewController) {
        SupportFlowCoordinator(from: self).openTransactionBrowser(controller.transactionID!)
    }

    public func transactionDetailsViewController(_ controller: TransactionDetailsViewController,
                                                 didSelectToEditNameForAddress address: String) {
        if ApplicationServiceRegistry.walletService.addressName(for: address) != nil {
            let entryID = ApplicationServiceRegistry.walletService.addressBookEntryID(for: address)!
            let vc = AddressBookEditEntryViewController.create(entryID: entryID, delegate: self)
            push(vc)
        } else {
            let vc = AddressBookEditEntryViewController.create(name: nil, address: address, delegate: self)
            push(vc)
        }
    }

    public func transactionDetailsViewController(_ controller: TransactionDetailsViewController,
                                                 didSelectToSendToken token: TokenData,
                                                 forAddress address: String) {
        createNewTransaction(token: token.address, address: address)
    }

}

// MARK: - MenuTableViewControllerDelegate

extension MainFlowCoordinator: MenuTableViewControllerDelegate {

    func didSelectCommand(_ command: MenuCommand) {
        command.run()
    }

}

// MARK: - AddressBookEditEntryViewControllerDelegate

extension MainFlowCoordinator: AddressBookEditEntryViewControllerDelegate {

    func addressBookEditEntryViewController(_ controller: AddressBookEditEntryViewController,
                                            didSave id: AddressBookEntryID) {
        pop()
    }

    func addressBookEditEntryViewController(_ controller: AddressBookEditEntryViewController,
                                            didDelete id: AddressBookEntryID) {
        pop()
    }

}
