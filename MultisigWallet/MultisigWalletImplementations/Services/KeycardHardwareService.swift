//
//  Copyright © 2019 Gnosis Ltd. All rights reserved.
//

import Foundation
import Keycard
import MultisigWalletDomainModel
import MultisigWalletApplication
import CoreNFC

typealias KeycardDomainServiceError = KeycardApplicationService.Error

public class KeycardHardwareService: KeycardDomainService {

    private var keycardController: KeycardController?

    private static let alertMessages = KeycardController.AlertMessages(
            LocalizedString("multiple_tags", comment: "Multiple tags found"),
            LocalizedString("unsupported_tag", comment: "Tag not supported"),
            LocalizedString("tag_connection_error", comment: "Tag error"))

    public init() {}

    public var isAvailable: Bool { return KeycardController.isAvailable }

    // this will create a pairing, if needed; generate master key if needed; derive the key;
    // then it will store the pairing and the derived key in the KeycardRepository.
    public func pair(password: String, pin: String, keyPathComponent: KeyPathComponent) throws -> Address {
        return try doPair(password: password,
                          pin: pin,
                          keyPathComponent: keyPathComponent) { [unowned self] cmdSet in
                            self.keycardController?.setAlert(LocalizedString("pairing_wait", comment: "Initializing"))

                            let info = try ApplicationInfo(cmdSet.select().checkOK().data)

                            if !info.initializedCard {
                                throw KeycardDomainServiceError.keycardNotInitialized
                            }
                            return info
        }
    }

    private static let ethereumMainnetHDWalletPath = "m/44'/60'/0'/0"
    private static let hdPathSeparator = "/"

    // NOTE: this method specifically kept long to make one whole flow of commands sent to the Keycard visible.
    private func doPair(password: String,
                        pin: String,
                        keyPathComponent: KeyPathComponent,
                        prepare: @escaping (KeycardCommandSet) throws -> ApplicationInfo) throws -> Address {
        assert(keycardController == nil, "KeycardController must be nil")
        dispatchPrecondition(condition: .notOnQueue(DispatchQueue.main))

        var result: Result<Address, Error>!

        let semaphore = DispatchSemaphore(value: 0)
        keycardController = KeycardController(alertMessages: KeycardHardwareService.alertMessages,
                                              onConnect: { channel in
            do {
                let cmdSet = KeycardCommandSet(cardChannel: channel)

                let info = try prepare(cmdSet)
                assert(!info.instanceUID.isEmpty, "Instance UID is not known in initialized card")

                var existingPairing = DomainRegistry.keycardRepository.findPairing(instanceUID: Data(info.instanceUID))

                if let pairing = existingPairing {
                    cmdSet.pairing = Pairing(pairingKey: Array(existingPairing!.key),
                                             pairingIndex: UInt8(existingPairing!.index))

                    // Even though we store the pairing in the app, it may become invalid if the user unpaired the slot
                    // that we use. Thus, we must check the validity of the pairing here.

                    // Tries to open secure channel and detect specific errors showing that pairing is invalid.
                    do {
                        // possible errors:
                        //   - CardError.notPaired: if the cmdSet.pairing is not set
                        //   - CardError.invalidAuthData: if the SDK did not authenticate the card
                        // from OPEN SECURE CHANNEL command:
                        //   - 0x6A86 if P1 is invalid: means that StatusWord.pairingIndexInvalid
                        //   - 0x6A80 if the data is not a public key: means that StatusWord.dataInvalid
                        //   - 0x6982 if a MAC cannot be verified: means that StatusWord.securityConditionNotSatisfied
                        // from MUTUALLY AUTHENTICATE command:
                        //   - 0x6985 if the previous successfully executed APDU was not OPEN SECURE CHANNEL.
                        //     This error should not happen unless there is error in Keycard SDK
                        //   - 0x6982 if authentication failed or the data is not 256-bit long
                        //     (StatusWord.securityConditionNotSatisfied). This indicates that the card
                        //     did not authenticate the app.
                        //
                        try cmdSet.autoOpenSecureChannel()
                    } catch let error where
                        error as? CardError == CardError.invalidAuthData ||
                        error as? StatusWord == StatusWord.pairingIndexInvalid ||
                        error as? StatusWord == StatusWord.dataInvalid ||
                        error as? StatusWord == StatusWord.securityConditionNotSatisfied {
                                // pairing is no longer valid, we'll try re-pair afterwards.
                                cmdSet.pairing = nil
                                DomainRegistry.keycardRepository.remove(pairing)
                                existingPairing = nil
                    }
                }

                if existingPairing == nil {
                    if info.freePairingSlots < 1 {
                        throw KeycardDomainServiceError.noPairingSlotsRemaining
                    }
                    do {
                        // Trying to pair and save the result.
                        //
                        // Here are possible errors according to the SDK API docs:
                        // from PAIR first step (P1=0x00) command:
                        //   - 0x6A80 if the data is in the wrong format.
                        //     Not expected at this point because SDK handles it
                        //   - 0x6982 if client cryptogram verification fails.
                        //     Not expected at this point because SDK sends random challenge.
                        //   - 0x6A84 if all available pairing slot are taken.
                        //     This can happen - StatusWord.allPairingSlotsTaken
                        //   - 0x6A86 if P1 is invalid or is 0x01 but the first phase was not completed
                        //     This should not happen as SDK should do it properly.
                        //   - 0x6985 if a secure channel is open
                        //     This should not happen because if existingPairing == nil then we
                        //     did not open secure channel yet.
                        //
                        // from PAIR second step (P1=0x01) command:
                        //   - 0x6A80 if the data is in the wrong format.
                        //     Not expected at this point because SDK handles it
                        //   - 0x6982 if client cryptogram verification fails.
                        //     This may happen because the pairing password is invalid.
                        //     (StatusWord.securityConditionNotSatisfied)
                        //   - 0x6A84 if all available pairing slot are taken.
                        //     This can happen - StatusWord.allPairingSlotsTaken
                        //   - 0x6A86 if P1 is invalid or is 0x01 but the first phase was not completed
                        //     This should not happen as SDK should do it properly.
                        //   - 0x6985 if a secure channel is open
                        //     This should not happen because if existingPairing == nil then we
                        //     did not open secure channel yet.
                        //
                        // CardError.invalidAuthData - if our pairing password does not match card's cryptogram
                        //
                        try cmdSet.autoPair(password: password)
                    } catch let error where
                            error as? CardError == CardError.invalidAuthData ||
                            error as? StatusWord == StatusWord.securityConditionNotSatisfied {
                                throw KeycardDomainServiceError.invalidPairingPassword
                    } catch StatusWord.allPairingSlotsTaken {
                        throw KeycardDomainServiceError.noPairingSlotsRemaining
                    }
                    assert(cmdSet.pairing != nil, "Pairing information not found after successful pairing")

                    existingPairing = KeycardPairing(instanceUID: Data(info.instanceUID),
                                                     index: Int(cmdSet.pairing!.pairingIndex),
                                                     key: Data(cmdSet.pairing!.pairingKey))
                    DomainRegistry.keycardRepository.save(existingPairing!)

                    // expected to succeed, no specific error handling here.
                    try cmdSet.autoOpenSecureChannel()
                }

                // Trying to authenticate with PIN for further key generation and derivation.
                //
                // Possible errors:
                //   - 0x63CX on failure, where X is the number of attempt remaining
                //   - 0x63C0 when the PIN is blocked, even if the PIN is inserted correctly.
                do {
                    try cmdSet.verifyPIN(pin: pin).checkAuthOK()
                } catch CardError.wrongPIN(retryCounter: let attempts) where attempts == 0 {
                    throw KeycardDomainServiceError.keycardBlocked
                } catch CardError.wrongPIN(retryCounter: let attempts) {
                    throw KeycardDomainServiceError.invalidPin(attempts)
                }

                var masterKeyUID = info.keyUID

                if masterKeyUID.isEmpty {
                    masterKeyUID = try cmdSet.generateKey().checkOK().data
                }

                let keypath = KeycardHardwareService.ethereumMainnetHDWalletPath +
                              KeycardHardwareService.hdPathSeparator +
                              String(keyPathComponent)
                let exportKeyData = try cmdSet.exportKey(path: keypath, makeCurrent: true, publicOnly: true).checkOK().data
                let bip32KeyPair = try BIP32KeyPair(fromTLV: exportKeyData)
                let derivedPublicKey = Data(bip32KeyPair.publicKey)
                let address = Address(EthereumKitEthereumService().createAddress(publicKey: derivedPublicKey))
                let key = KeycardKey(address: address,
                                     instanceUID: Data(info.instanceUID),
                                     masterKeyUID: Data(masterKeyUID),
                                     keyPath: keypath,
                                     publicKey: derivedPublicKey)
                DomainRegistry.keycardRepository.save(key)

                result = .success(address)
                self.keycardController?.stop(alertMessage: LocalizedString("success", comment: "Success"))
            } catch let error as NFCReaderError {
                result = .failure(error)
                if error.code == NFCReaderError.readerTransceiveErrorTagConnectionLost {
                    self.keycardController?.stop(errorMessage: LocalizedString("tag_connection_lost",
                                                                               comment: "Lost connection"))
                }
            } catch {
                result = .failure(error)
                self.keycardController?.stop(errorMessage: LocalizedString("operation_failed",
                                                                           comment: "Operation failed"))
            }
            semaphore.signal()
        }, onFailure: { error in
            result = .failure(error)
            if let readerError = error as? NFCReaderError {
                switch readerError.code {
                    case NFCReaderError.readerSessionInvalidationErrorSessionTimeout,
                         NFCReaderError.readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
                        result = .failure(KeycardApplicationService.Error.timeout)
                    case NFCReaderError.readerSessionInvalidationErrorUserCanceled,
                         NFCReaderError.readerSessionInvalidationErrorSystemIsBusy:
                        result = .failure(KeycardApplicationService.Error.userCancelled)
                    default:
                        break
                }
            }
            semaphore.signal()
        })

        keycardController?.start(alertMessage: LocalizedString("hold_near_card", comment: "Hold device near the card"))
        semaphore.wait()
        keycardController = nil

        assert(result != nil, "Result must be set after pairing")
        switch result! {
        case .success(let address):
            return address
        case .failure(let error):
            throw error
        }

    }

    private static let pinPukAlphabet = "0123456789"
    private static let passwordAlphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890+-=!@$#*&?"
    private static let pinLength = 6
    private static let pukLength = 12
    private static let pairingPasswordLength = 12

    public func generateCredentials() -> (pin: String, puk: String, pairingPassword: String) {
        // simple N out of M random algorithm. Did not use more advanced idea in lieu of simplicity.
        func randomString(length: Int, alphabet: String) -> String {
            guard length > 0 && !alphabet.isEmpty else { return "" }
            return (0..<length).map { _ in String(alphabet.randomElement()!) }.joined()
        }
        return (pin: randomString(length: KeycardHardwareService.pinLength,
                                  alphabet: KeycardHardwareService.pinPukAlphabet),
                puk: randomString(length: KeycardHardwareService.pukLength,
                                  alphabet: KeycardHardwareService.pinPukAlphabet),
                pairingPassword: randomString(length: KeycardHardwareService.pairingPasswordLength,
                                              alphabet: KeycardHardwareService.passwordAlphabet))
    }

    //  Initializes the card, pairs it, generates master key, and derives a signing key by key_component
    public func initialize(pin: String, puk: String, pairingPassword: String, keyPathComponent: KeyPathComponent) throws -> Address  {
        return try doPair(password: pairingPassword,
                          pin: pin,
                          keyPathComponent: keyPathComponent) { [unowned self] cmdSet in

                            self.keycardController?.setAlert(LocalizedString("initializing_wait", comment: "Initializing"))

                            let info = try ApplicationInfo(cmdSet.select().checkOK().data)

                            if info.initializedCard {
                                throw KeycardDomainServiceError.keycardAlreadyInitialized
                            }

                            // Possible errors:
                            //   - 0x6D00 if the applet is already initialized. Might happen.
                            //   - 0x6A80 if the data is invalid. Not expected because SDK formats the data properly.
                            do {
                                try cmdSet.initialize(pin: pin, puk: puk, pairingPassword: pairingPassword).checkOK()
                            } catch StatusWord.alreadyInitialized {
                                throw KeycardDomainServiceError.keycardAlreadyInitialized
                            }

                            return try ApplicationInfo(cmdSet.select().checkOK().data)
        }
    }

    // we do not remove pairing on purpose in order not to spoil too many pairing slots.
    // every time the same card goes through the pairing process, we will reuse existing pairing.
    public func forgetKey(for address: Address) {
        if let key = DomainRegistry.keycardRepository.findKey(with: address) {
            DomainRegistry.keycardRepository.remove(key)
        }
    }

}
