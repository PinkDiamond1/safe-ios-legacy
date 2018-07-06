//
//  Copyright © 2018 Gnosis Ltd. All rights reserved.
//

import XCTest
@testable import safe
import MultisigWalletDomainModel
import EthereumDomainModel
import EthereumImplementations
import MultisigWalletImplementations
import Common

class HTTPNotificatonServiceTests: XCTestCase {

    let notificationService = HTTPNotificationService()
    let ethService = EthereumKitEthereumService()
    var encryptionService: EncryptionService!
    var browserExtensionEOA: ExternallyOwnedAccount!
    var deviceEOA: ExternallyOwnedAccount!

    override func setUp() {
        super.setUp()
        encryptionService = EncryptionService(chainId: .any,
                                              ethereumService: ethService)
        browserExtensionEOA = try! encryptionService.generateExternallyOwnedAccount()
        deviceEOA = try! encryptionService.generateExternallyOwnedAccount()

    }

    func test_whenGoodData_thenReturnsSomething() throws {
        let code = try browserExtensionCode(expirationDate: Date(timeIntervalSinceNow: 5 * 60))
        let sig = try signature()
        let pairingRequest = PairingRequest(
            temporaryAuthorization: code,
            signature: sig,
            deviceOwnerAddress: deviceEOA.address.value)
        try notificationService.pair(pairingRequest: pairingRequest)
    }

    func test_whenBrowserExtensionCodeIsExpired_thenThrowsError() throws {
        let code = try browserExtensionCode(expirationDate: Date(timeIntervalSinceNow: -5 * 60))
        let sig = try signature()
        let pairingRequest = PairingRequest(
            temporaryAuthorization: code,
            signature: sig,
            deviceOwnerAddress: deviceEOA.address.value)

        do {
            try notificationService.pair(pairingRequest: pairingRequest)
            XCTFail("Pairing call should faild for expired browser extension")
        } catch let e as JSONHTTPClient.Error {
            switch e {
            case let .networkRequestFailed(_, response, data):
                XCTAssertNotNil(response)
                XCTAssertNotNil(data)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 400)
                let responseDataString = String(data: data!, encoding: .utf8)
                XCTAssertTrue(responseDataString?.range(of: "Exceeded expiration date") != nil)
            }
        }
    }

    private func browserExtensionCode(expirationDate: Date) throws -> BrowserExtensionCode {
        let dateStr = DateFormatter.networkDateFormatter.string(from: expirationDate)

        let (r, s, v) = try encryptionService.sign(
            message: "GNO" + dateStr, privateKey: browserExtensionEOA.privateKey)
        let browserExtensionSignature = RSVSignature(r: r, s: s, v: v)
        return BrowserExtensionCode(
            expirationDate: expirationDate,
            signature: browserExtensionSignature,
            extensionAddress: browserExtensionEOA.address.value)
    }

    private func signature() throws -> MultisigWalletDomainModel.RSVSignature {
        let address = browserExtensionEOA.address.value
        let (r1, s1, v1) = try encryptionService.sign(message: "GNO" + address, privateKey: deviceEOA.privateKey)
        return RSVSignature(r: r1, s: s1, v: v1)
    }

}