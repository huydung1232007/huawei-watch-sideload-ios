import UIKit
import UniformTypeIdentifiers

final class MapShareViewController: UIViewController {
    private let message = UILabel()
    private let detail = UILabel()
    private var task: Task<Void,Never>?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        preferredContentSize = CGSize(width:390,height:400)
        let icon = UIImageView(image:UIImage(systemName:"map.fill"))
        icon.tintColor = .systemBlue; icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant:52).isActive = true
        let title = UILabel(); title.text = "HuaSideload"; title.font = .preferredFont(forTextStyle:.title2)
        title.textAlignment = .center
        message.text = "Đang nhận địa điểm…"; message.font = .preferredFont(forTextStyle:.headline)
        message.textAlignment = .center; message.numberOfLines = 0
        detail.font = .preferredFont(forTextStyle:.subheadline); detail.textColor = .secondaryLabel
        detail.numberOfLines = 0; detail.textAlignment = .center
        var configuration = UIButton.Configuration.filled(); configuration.title = "Xong"
        configuration.cornerStyle = .large
        let done = UIButton(configuration:configuration,primaryAction:UIAction { [weak self] _ in
            self?.task?.cancel(); self?.extensionContext?.completeRequest(returningItems:nil)
        })
        let stack = UIStackView(arrangedSubviews:[icon,title,message,detail,done])
        stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:24),
            stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-24),
            stack.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-16)])
        task = Task { await receivePlace() }
    }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); task?.cancel() }
    private func receivePlace() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var links = Set<String>()
        for item in items {
            if let text = item.attributedContentText?.string,let envelope = try? MapShareEnvelope(text:text) { links.insert(envelope.link) }
        }
        for provider in items.flatMap({ $0.attachments ?? [] }).prefix(8) {
            for type in [UTType.url.identifier, UTType.plainText.identifier] where provider.hasItemConformingToTypeIdentifier(type) {
                guard !Task.isCancelled else { return }
                if let text = try? await load(provider,type:type), let envelope = try? MapShareEnvelope(text:text) {
                    links.insert(envelope.link); break
                }
            }
        }
        guard !Task.isCancelled else { return }
        guard links.count == 1,let link = links.first,let envelope = try? MapShareEnvelope(text:link),
              let data = try? JSONEncoder().encode(envelope) else {
            message.text = "Chưa nhận được một địa điểm Google Maps hợp lệ."
            detail.text = "Chia sẻ liên kết của một địa điểm hoặc ghim, rồi thử lại."
            return
        }
        UIPasteboard.general.setItems([[MapShareEnvelope.pasteboardType:data,
            UTType.url.identifier:URL(string:envelope.link)!]],
            options:[.localOnly:true,.expirationDate:Date().addingTimeInterval(600)])
        message.text = "Đã nhận địa điểm"
        detail.text = "Mở HuaSideload trong 10 phút để xem ghim và chọn tuyến. Cho phép dán khi iOS hỏi. Bạn cũng có thể thêm địa điểm này làm điểm dừng."
    }
    private func load(_ provider: NSItemProvider,type: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier:type,options:nil) { value,error in
                if let error { continuation.resume(throwing:error); return }
                if let url = value as? URL { continuation.resume(returning:url.absoluteString) }
                else if let text = value as? String { continuation.resume(returning:text) }
                else if let data = value as? Data, data.count <= 16_384,let text = String(data:data,encoding:.utf8) {
                    continuation.resume(returning:text)
                } else { continuation.resume(throwing:MapPlaceLink.LinkError.invalidLink) }
            }
        }
    }
}
