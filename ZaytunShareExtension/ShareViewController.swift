import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        titleLabel.text = "Save to Zaytun"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true

        statusLabel.text = "Images, audio, and video will be added to Inbox."
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true

        saveButton.configuration = .filled()
        saveButton.configuration?.title = "Save"
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)

        cancelButton.configuration = .plain()
        cancelButton.configuration?.title = "Cancel"
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [cancelButton, saveButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            statusLabel,
            activityIndicator,
            buttonStack,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 18
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func save() {
        setBusy(true)
        Task {
            do {
                let queue = try SharedImportQueue.appGroup()
                let providers = inputProviders()
                guard !providers.isEmpty else {
                    throw SharedImportQueueError.unsupportedContentType("No media")
                }
                try await stage(providers: providers, in: queue)
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                setBusy(false)
                statusLabel.text = error.localizedDescription
                statusLabel.textColor = .systemRed
            }
        }
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(
                domain: "com.hassanemeite.zaytun.share",
                code: NSUserCancelledError
            )
        )
    }

    private func inputProviders() -> [NSItemProvider] {
        (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { SharedMediaKind.detect(typeIdentifiers: $0.registeredTypeIdentifiers) != nil }
    }

    private func stage(
        providers: [NSItemProvider],
        in queue: SharedImportQueue
    ) async throws {
        var stagedEntries: [SharedImportEntry] = []
        do {
            for provider in providers {
                stagedEntries.append(try await stage(provider: provider, in: queue))
            }
        } catch {
            for entry in stagedEntries {
                try? queue.remove(entry)
            }
            throw error
        }
    }

    private func stage(
        provider: NSItemProvider,
        in queue: SharedImportQueue
    ) async throws -> SharedImportEntry {
        guard let (_, contentType) = SharedMediaKind.detect(
            typeIdentifiers: provider.registeredTypeIdentifiers
        ) else {
            throw SharedImportQueueError.unsupportedContentType(
                provider.registeredTypeIdentifiers.joined(separator: ", ")
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: contentType.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: SharedImportQueueError.missingPayload)
                    return
                }
                do {
                    let entry = try queue.stage(
                        sourceURL: url,
                        contentType: contentType,
                        originalFilename: url.lastPathComponent
                    )
                    continuation.resume(returning: entry)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func setBusy(_ isBusy: Bool) {
        saveButton.isEnabled = !isBusy
        cancelButton.isEnabled = !isBusy
        if isBusy {
            activityIndicator.startAnimating()
            statusLabel.text = "Preparing media…"
            statusLabel.textColor = .secondaryLabel
        } else {
            activityIndicator.stopAnimating()
        }
    }
}
