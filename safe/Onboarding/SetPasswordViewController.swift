//
//  Copyright © 2018 Gnosis. All rights reserved.
//

import UIKit

final class SetPasswordViewController: UIViewController {

    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var minimumLengthRuleLabel: RuleLabel!
    @IBOutlet weak var capitalLetterRuleLabel: RuleLabel!
    @IBOutlet weak var digitRuleLabel: RuleLabel!

    let minCharsInPassword = 6

    static func create() -> SetPasswordViewController {
        return StoryboardScene.Onboarding.setPasswordViewController.instantiate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        passwordTextField.delegate = self
        passwordTextField.becomeFirstResponder()
    }

    func setMinimumLengthRuleStatus(_ status: RuleStatus) {
        minimumLengthRuleLabel.status = status
    }

    func setCapitalLetterRuleStatus(_ status: RuleStatus) {
        capitalLetterRuleLabel.status = status
    }

    func setDigitRuleStatus(_ status: RuleStatus) {
        digitRuleLabel.status = status
    }

}

extension SetPasswordViewController: UITextFieldDelegate {

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        let oldText = (textField.text ?? "") as NSString
        let newText = oldText.replacingCharacters(in: range, with: string)
        guard !newText.isEmpty else {
            setRulesIntoInitialStatus()
            return true
        }
        setCapitalLetterRuleStatus(newText.containsCapitalizedLetter() ? .success : .error)
        setDigitRuleStatus(newText.containsDigit() ? .success : .error)
        setMinimumLengthRuleStatus(newText.count >= minCharsInPassword ?  .success : .error)
        return true
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        setRulesIntoInitialStatus()
        return true
    }

    private func setRulesIntoInitialStatus() {
        setMinimumLengthRuleStatus(.inactive)
        setCapitalLetterRuleStatus(.inactive)
        setDigitRuleStatus(.inactive)
    }

}