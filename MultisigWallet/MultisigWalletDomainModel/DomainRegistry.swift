//
//  Copyright © 2018 Gnosis Ltd. All rights reserved.
//

import Foundation
import Common

/// Service locator for domain services and repositories
public class DomainRegistry: AbstractRegistry {

    // MARK: - Repositories

    public static var walletRepository: WalletRepository {
        return service(for: WalletRepository.self)
    }

    public static var portfolioRepository: SinglePortfolioRepository {
        return service(for: SinglePortfolioRepository.self)
    }

    public static var accountRepository: AccountRepository {
        return service(for: AccountRepository.self)
    }

    public static var externallyOwnedAccountRepository: ExternallyOwnedAccountRepository {
        return service(for: ExternallyOwnedAccountRepository.self)
    }

    public static var transactionRepository: TransactionRepository {
        return service(for: TransactionRepository.self)
    }

    public static var tokenListItemRepository: TokenListItemRepository {
        return service(for: TokenListItemRepository.self)
    }

    public static var safeContractMetadataRepository: SafeContractMetadataRepository {
        return service(for: SafeContractMetadataRepository.self)
    }

    public static var walletConnectSessionRepository: WalletConnectSessionRepository {
        return service(for: WalletConnectSessionRepository.self)
    }

    public static var appSettingsRepository: AppSettingsRepository {
        return service(for: AppSettingsRepository.self)
    }

    public static var keycardRepository: KeycardRepository {
        return service(for: KeycardRepository.self)
    }

    public static var transactionMonitorRepository: RBETransactionMonitorRepository {
        return service(for: RBETransactionMonitorRepository.self)
    }

    public static var addressBookRepository: AddressBookRepository {
        return service(for: AddressBookRepository.self)
    }

    // MARK: - Services

    public static var notificationService: NotificationDomainService {
        return service(for: NotificationDomainService.self)
    }

    public static var encryptionService: EncryptionDomainService {
        return service(for: EncryptionDomainService.self)
    }

    public static var transactionRelayService: TransactionRelayDomainService {
        return service(for: TransactionRelayDomainService.self)
    }

    public static var ethereumNodeService: EthereumNodeDomainService {
        return service(for: EthereumNodeDomainService.self)
    }

    public static var tokenListService: TokenListDomainService {
        return service(for: TokenListDomainService.self)
    }

    public static var syncService: SynchronisationDomainService {
        return service(for: SynchronisationDomainService.self)
    }

    public static var eventPublisher: EventPublisher {
        return service(for: EventPublisher.self)
    }

    public static var errorStream: ErrorStream {
        return service(for: ErrorStream.self)
    }

    public static var system: System {
        return service(for: System.self)
    }

    public static var deploymentService: DeploymentDomainService {
        return service(for: DeploymentDomainService.self)
    }

    public static var accountUpdateService: AccountUpdateDomainService {
        return service(for: AccountUpdateDomainService.self)
    }

    public static var transactionService: TransactionDomainService {
        return service(for: TransactionDomainService.self)
    }

    public static var recoveryService: RecoveryDomainService {
        return service(for: RecoveryDomainService.self)
    }

    public static var replacePhraseService: ReplaceRecoveryPhraseDomainService {
        return service(for: ReplaceRecoveryPhraseDomainService.self)
    }

    public static var replace2FAService: ReplaceTwoFADomainService {
        return service(for: ReplaceTwoFADomainService.self)
    }

    public static var connectTwoFAService: ConnectTwoFADomainService {
        return service(for: ConnectTwoFADomainService.self)
    }

    public static var disconnectTwoFAService: DisconnectTwoFADomainService {
        return service(for: DisconnectTwoFADomainService.self)
    }

    public static var contractUpgradeService: ContractUpgradeDomainService {
        return service(for: ContractUpgradeDomainService.self)
    }

    public static var communicationService: CommunicationDomainService {
        return service(for: CommunicationDomainService.self)
    }

    public static var walletConnectService: WalletConnectDomainService {
        return service(for: WalletConnectDomainService.self)
    }

    public static var diagnosticService: WalletDiagnosticService {
        return service(for: WalletDiagnosticService.self)
    }

    public static var keycardService: KeycardDomainService {
        return service(for: KeycardDomainService.self)
    }

    public static var ensService: ENSDomainService {
        return service(for: ENSDomainService.self)
    }

    public static var logger: Logger {
        return service(for: Logger.self)
    }

}
