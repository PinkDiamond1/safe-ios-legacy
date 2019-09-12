//
//  Copyright © 2019 Gnosis Ltd. All rights reserved.
//

import Foundation
import UIKit
import SafeUIKit
import MultisigWalletApplication

protocol SKPairViewControllerDelegate: class {
    func pairViewControllerDidPairSuccessfully(_ controller: SKPairViewController)
    func pairViewControllerNeedsInitialization(_ controller: SKPairViewController)
    func pairViewControllerNeedsToGetInTouch(_ controller: SKPairViewController)
}

class SKPairViewController: UIViewController {

    @IBOutlet weak var scrollView: UIScrollView!

    @IBOutlet weak var titleLabel: UILabel!

    @IBOutlet weak var pairingPasswordField: VerifiableInput!
    @IBOutlet weak var pinField: VerifiableInput!

    @IBOutlet weak var pairButton: StandardButton!
    @IBOutlet weak var initializeButton: StandardButton!

    private var keyboardBehavior: KeyboardAvoidingBehavior!

    weak var delegate: SKPairViewControllerDelegate?

    private static let pinLength = 6
    private static let inputHeight: CGFloat = 56

    static func create(delegate: SKPairViewControllerDelegate) -> SKPairViewController {
        let controller = StoryboardScene.CreateSafe.skPairViewController.instantiate()
        controller.delegate = delegate
        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = LocalizedString("pair_2fa_device", comment: "Pair 2FA device")

        titleLabel.text = LocalizedString("enter_pass_pin", comment: "Enter password and PIN")
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        titleLabel.textAlignment = .center
        titleLabel.textColor = ColorName.darkGrey.color

        keyboardBehavior = KeyboardAvoidingBehavior(scrollView: scrollView)

        pairingPasswordField.isSecure = true
        pairingPasswordField.style = .white
        pairingPasswordField.textInput.placeholder = LocalizedString("pairing_password", comment: "Password")
        pairingPasswordField.showErrorsOnly = true

        pinField.isSecure = true
        pinField.style = .white
        pinField.textInput.placeholder = LocalizedString("pin", comment: "PIN")
        pinField.textInput.keyboardType = .numberPad
        pinField.showErrorsOnly = true

        pairingPasswordField.delegate = self
        pinField.delegate = self

        pairingPasswordField.addRule(LocalizedString("not_empty", comment: "Not empty")) { text in
            return !text.isEmpty
        }

        pinField.addRule(LocalizedString("not_empty", comment: "Not empty")) { text in
            return !text.isEmpty
        }
        pinField.addRule(LocalizedString("only_digits", comment: "Use digits only")) { text in
            return text.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
        }
        let pinLengthText = String(format: LocalizedString("exactly_x_digits", comment: "Exactly x digits"),
                                   SKPairViewController.pinLength)
        pinField.addRule(pinLengthText) { text in
            return text.count == SKPairViewController.pinLength
        }

        pairButton.style = .filled
        pairButton.setTitle(LocalizedString("pair_keycard", comment: "Pair Keycard"), for: .normal)

        initializeButton.style = .plain
        initializeButton.setTitle(LocalizedString("have_no_password", comment: "I have no password"), for: .normal)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboardBehavior.start()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        trackEvent(OnboardingTrackingEvent.pair2FADevice)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keyboardBehavior.stop()
    }

    func didEnterValidTextInPairingPasswordField() {
        updateButtonsEnabled()
        _ = pinField.becomeFirstResponder()
    }

    func updateButtonsEnabled() {
        setButtons(enabled: pairingPasswordField.isValid && pinField.isValid)
    }

    func setButtons(enabled: Bool) {
        pairButton.isEnabled = enabled
        initializeButton.isEnabled = enabled
    }

    func didEnterValidTextInPinField() {
        updateButtonsEnabled()
        pairKeycard()
    }

    var isPairingInProgress = false

    @IBAction @objc func pairKeycard() {
        guard !isPairingInProgress else { return }
        isPairingInProgress = true

        setButtons(enabled: false)

        assert(pairingPasswordField.text != nil, "pairing password is nil")
        assert(!pairingPasswordField.text!.isEmpty, "pairing password is empty")
        let password = pairingPasswordField.text!

        assert(pinField.text != nil, "pin is nil")
        assert(pinField.text?.count == SKPairViewController.pinLength,
               "pin count is not \(SKPairViewController.pinLength)")
        let pin = pinField.text!

        DispatchQueue.global().async { [weak self] in
            guard let `self` = self else { return }
            do {
                try ApplicationServiceRegistry.keycardService.pair(password: password, pin: pin)
                self.isPairingInProgress = false

                DispatchQueue.main.async {
                    self.delegate?.pairViewControllerDidPairSuccessfully(self)
                }
            } catch {
                self.isPairingInProgress = false
                DispatchQueue.main.async {
                    self.setButtons(enabled: true)
                    self.showError(error)
                }
            }

        }
    }

    func showError(_ error: Error) {
        switch error {

        case KeycardApplicationService.Error.invalidPairingPassword:
            self.pairingPasswordField.setExplicitError(LocalizedString("pairing_failed_password",
                                                                       comment: "Wrong password"))

        case KeycardApplicationService.Error.invalidPin(let attempts):
            let errorText = String(format: LocalizedString("pairing_failed_pin_x_attempts",
                                                           comment: "Wrong pin"),
                                   attempts)
            self.pinField.setExplicitError(errorText)

        case KeycardApplicationService.Error.noPairingSlotsRemaining:
            let title = LocalizedString("no_slots_available", comment: "No more slots")
            let message = LocalizedString("all_slots_in_use", comment: "Description of no more slots")
            self.present(UIAlertController.create(title: title, message: message).withCloseAction(),
                         animated: true)

        case KeycardApplicationService.Error.keycardBlocked:
            let title = LocalizedString("keycard_blocked", comment: "Blocked")
            let message = LocalizedString("keycard_unblock_get_in_touch", comment: "Get in touch")
            let getInTouch = LocalizedString("get_in_touch", comment: "Get In Touch")
            self.present(UIAlertController.create(title: title, message: message)
                .withCancelAction()
                .withDefaultAction(title: getInTouch, handler: {
                    self.delegate?.pairViewControllerNeedsToGetInTouch(self)
                }), animated: true)

        case KeycardApplicationService.Error.keycardNotInitialized:
            let title = LocalizedString("keycard_uninitialized", comment: "Not initialized")
            let message = LocalizedString("want_to_initialize", comment: "Do you want to do it?")
            let initialize = LocalizedString("initialize", comment: "Initialize")
            self.present(UIAlertController.create(title: title, message: message)
                .withCancelAction()
                .withDefaultAction(title: initialize, handler: {
                    self.delegate?.pairViewControllerNeedsInitialization(self)
                }), animated: true)

        case KeycardApplicationService.Error.userCancelled,
             KeycardApplicationService.Error.timeout:
            // do nothing
            break

        default:
            let errorText = LocalizedString("ios_error_description",
                                            comment: "Generic error message. Try again.")
            self.present(UIAlertController.operationFailed(message: errorText), animated: true)
        }
    }

    @IBAction @objc func initializeKeycard() {
        delegate?.pairViewControllerNeedsInitialization(self)
    }

}

extension SKPairViewController: VerifiableInputDelegate {

    func verifiableInputDidReturn(_ verifiableInput: VerifiableInput) {
        if verifiableInput === pairingPasswordField {
            didEnterValidTextInPairingPasswordField()
        } else if verifiableInput === pinField {
            didEnterValidTextInPinField()
        }
    }

    func verifiableInputDidBeginEditing(_ verifiableInput: VerifiableInput) {
        keyboardBehavior.activeTextField = verifiableInput.textInput
    }

}
