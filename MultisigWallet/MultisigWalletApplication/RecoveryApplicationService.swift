//
//  Copyright © 2018 Gnosis Ltd. All rights reserved.
//

import Foundation
import MultisigWalletDomainModel
import Common

public enum RecoveryApplicationServiceError: Error {
    case invalidContractAddress
    case walletAlreadyExists
    case recoveryPhraseInvalid
    case recoveryAccountsNotFound
    case unsupportedOwnerCount
    case unsupportedWalletConfiguration
    case failedToChangeOwners
    case failedToChangeConfirmationCount
    case failedToCreateValidTransactionData
    case walletNotFound
    case failedToCreateValidTransaction
    case internalServerError
}

public class RecoveryApplicationService {

    public init() {}

    public func createRecoverDraftWallet() {
        DomainRegistry.recoveryService.createRecoverDraftWallet()
    }

    public func validate(address: String,
                         subscriber: EventSubscriber,
                         onError errorHandler: @escaping (Error) -> Void) {
        withEnvironment(for: subscriber, errorHandler: errorHandler) {
            ApplicationServiceRegistry.eventRelay.subscribe(subscriber, for: WalletAddressChanged.self)
            DomainRegistry.recoveryService.change(address: Address(address))
        }
    }

    public func provide(recoveryPhrase: String,
                        subscriber: EventSubscriber,
                        onError errorHandler: @escaping (Error) -> Void) {
        withEnvironment(for: subscriber, errorHandler: errorHandler) {
            ApplicationServiceRegistry.eventRelay.subscribe(subscriber, for: WalletRecoveryAccountsAccepted.self)
            DomainRegistry.recoveryService.provide(recoveryPhrase: recoveryPhrase)
        }
    }

    public func verifyRecoveryPhrase(_ phrase: String, id: String) throws {
        guard let wallet = DomainRegistry.walletRepository.find(id: WalletID(id)) else {
            throw RecoveryApplicationServiceError.invalidContractAddress
        }
        do {
            try _ = DomainRegistry.recoveryService.verifyRecovery(wallet: wallet, recoveryPhrase: phrase)
        } catch {
            throw RecoveryApplicationService.applicationError(from: error)
        }
    }

    public func estimateRecoveryTransaction() -> [TokenData] {
        return DomainRegistry.recoveryService.estimateRecoveryTransaction()
    }

    public func createRecoveryTransaction(subscriber: EventSubscriber,
                                          onError errorHandler: @escaping (Error) -> Void) {
        withEnvironment(for: subscriber, errorHandler: errorHandler) {
            ApplicationServiceRegistry.eventRelay.subscribe(subscriber, for: WalletBecameReadyForRecovery.self)
            ApplicationServiceRegistry.eventRelay.subscribe(subscriber, for: AccountsBalancesUpdated.self)
            DomainRegistry.recoveryService.createRecoveryTransaction()
        }
    }

    public func recoveryTransaction(walletID: String) -> TransactionData? {
        guard let wallet = DomainRegistry.walletRepository.find(id: WalletID(walletID)),
            let tx = DomainRegistry.transactionRepository.find(type: .walletRecovery, wallet: wallet.id) else {
            return nil
        }
        return transactionData(tx)
    }

    public func transactionData(_ tx: String) -> TransactionData {
        let tx = DomainRegistry.transactionRepository.find(id: TransactionID(tx))!
        return transactionData(tx)
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func transactionData(_ tx: Transaction) -> TransactionData {
        let amount = tx.amount ?? TokenAmount(amount: 0, token: Token.Ether)
        let amountTokenData = TokenData(token: amount.token, balance: amount.amount)
        let paymentToken = WalletDomainService.token(id: tx.accountID.tokenID.id) ?? Token.Ether
        let zeroGasPrice = TokenAmount(amount: 0, token: paymentToken)
        let zeroFeeEstimate = TransactionFeeEstimate(gas: 0, dataGas: 0, operationalGas: 0, gasPrice: zeroGasPrice)
        let feeEstimate = tx.feeEstimate ?? zeroFeeEstimate
        let feeTokenData = TokenData(token: paymentToken, balance: -feeEstimate.totalDisplayedToUser.amount)
        let sender = tx.sender!.value
        let senderName = ApplicationServiceRegistry.walletService.addressName(for: sender)
        let recipient = tx.recipient!.value
        let recipientName = ApplicationServiceRegistry.walletService.addressName(for: recipient)
        return TransactionData(id: tx.id.id,
                               walletID: tx.accountID.walletID.id,
                               sender: sender,
                               senderName: senderName,
                               recipient: recipient,
                               recipientName: recipientName,
                               amountTokenData: amountTokenData,
                               feeTokenData: feeTokenData,
                               subtransactions: nil,
                               dataByteCount: nil,
                               status: tx.status.transactionDataStatus,
                               type: tx.type.transactionDataType,
                               created: tx.createdDate,
                               updated: tx.updatedDate,
                               submitted: tx.submittedDate,
                               rejected: tx.rejectedDate,
                               processed: tx.processedDate)
    }

    public func isRecoveryTransactionReadyToSubmit() -> Bool {
        return DomainRegistry.recoveryService.isRecoveryTransactionReadyToSubmit()
    }

    public func isRecoveryInProgress() -> Bool {
        return DomainRegistry.recoveryService.isRecoveryInProgress()
    }

    public func cancelRecovery(walletID: String) {
        DomainRegistry.recoveryService.cancelRecovery(walletID: WalletID(walletID))
    }

    public func isRecoveryTransactionConnectsAuthenticator(_ id: String) -> Bool {
        return DomainRegistry.recoveryService.isTransactionConnectsAuthenticator(TransactionID(id))
    }

    public func resumeRecovery(subscriber: EventSubscriber,
                               onError errorHandler: @escaping (Error) -> Void) {
        guard let walletID = DomainRegistry.walletRepository.selectedWallet()?.id else { return }
        withEnvironment(for: subscriber, errorHandler: errorHandler) {
            ApplicationServiceRegistry.eventRelay.subscribe(subscriber, for: WalletRecovered.self)
            ApplicationServiceRegistry.eventRelay.subscribe(subscriber, for: RecoveryTransactionHashIsKnown.self)
            DomainRegistry.recoveryService.resume(walletID: walletID)
        }
    }

    public func resumeRecoveryInBackground() {
        let walletIDs = DomainRegistry.walletRepository.all().filter { $0.isRecoveryInProgress }.map { WalletID($0.id.id) }
        for walletID in walletIDs {
            DispatchQueue.global().async {
                DomainRegistry.recoveryService.resume(walletID: walletID)
            }
        }
    }

    // MARK: - Execution environment setup

    private func withEnvironment(for subscriber: EventSubscriber,
                                 errorHandler:  @escaping (Error) -> Void,
                                 closure: () -> Void) {
        setUpEnvironment(for: subscriber, errorHandler: errorHandler)
        closure()
    }

    private func setUpEnvironment(for subscriber: EventSubscriber, errorHandler:  @escaping (Error) -> Void) {
        DomainRegistry.errorStream.removeHandler(self)
        DomainRegistry.errorStream.addHandler(self) { error in
            errorHandler(RecoveryApplicationService.applicationError(from: error))
        }
        ApplicationServiceRegistry.eventRelay.unsubscribe(subscriber)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func applicationError(from domainError: Error) -> Error {
        switch domainError {
        case RecoveryServiceError.invalidContractAddress:
            return RecoveryApplicationServiceError.invalidContractAddress
        case RecoveryServiceError.walletAlreadyExists:
            return RecoveryApplicationServiceError.walletAlreadyExists
        case RecoveryServiceError.recoveryPhraseInvalid:
            return RecoveryApplicationServiceError.recoveryPhraseInvalid
        case RecoveryServiceError.recoveryAccountsNotFound:
            return RecoveryApplicationServiceError.recoveryAccountsNotFound
        case RecoveryServiceError.unsupportedOwnerCount:
            return RecoveryApplicationServiceError.unsupportedOwnerCount
        case RecoveryServiceError.unsupportedWalletConfiguration:
            return RecoveryApplicationServiceError.unsupportedWalletConfiguration
        case RecoveryServiceError.failedToChangeOwners:
            return RecoveryApplicationServiceError.failedToChangeOwners
        case RecoveryServiceError.failedToChangeConfirmationCount:
            return RecoveryApplicationServiceError.failedToChangeConfirmationCount
        case RecoveryServiceError.failedToCreateValidTransactionData:
            return RecoveryApplicationServiceError.failedToCreateValidTransactionData
        case RecoveryServiceError.walletNotFound:
            return RecoveryApplicationServiceError.walletNotFound
        case RecoveryServiceError.failedToCreateValidTransaction:
            return RecoveryApplicationServiceError.failedToCreateValidTransaction
        case RecoveryServiceError.internalServerError:
            return RecoveryApplicationServiceError.internalServerError
        default:
            return domainError
        }
    }

}
