//
//  Copyright © 2018 Gnosis. All rights reserved.
//

import Foundation
import XCTest

final class SetPasswordScreen: SecureTextfieldScreen {

    struct Rules {

        let minimumLength = Rule(key: "onboarding.set_password.length")
        let capitalLetter = Rule(key: "onboarding.set_password.capital")
        let digit = Rule(key: "onboarding.set_password.digit")

        var all: [Rule] {
            return [minimumLength, capitalLetter, digit]
        }

    }

    override var title: XCUIElement {
        return XCUIApplication().staticTexts[XCLocalizedString("onboarding.set_password.header")]
    }
    var rules = Rules()

}
