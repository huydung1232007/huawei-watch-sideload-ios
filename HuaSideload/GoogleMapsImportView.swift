import MapKit
import SwiftUI

struct GoogleMapsImportView: View {
    @ObservedObject var navigator: RouteNavigator
    @ObservedObject var favorites: FavoritePlacesStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var loading = false
    @State private var message = ""
    @State private var isError = false
    @State private var results: [RouteNavigator.Destination] = []
    @State private var pin: SelectedMapPin?
    @State private var requestID = UUID()
    @State private var operation: Task<Void,Never>?
    @State private var search: MKLocalSearch?
    private let automaticallyResolve: Bool
    @State private var resolvedInitialInput = false

    init(navigator: RouteNavigator,favorites: FavoritePlacesStore,initialInput: String? = nil,automaticallyResolve: Bool = false) {
        self.navigator = navigator; self.favorites = favorites
        self.automaticallyResolve = automaticallyResolve
        _input = State(initialValue:initialInput ?? "")
    }

    var body: some View {
        Group {
            if let pin { MapPinDestinationView(pin:pin,navigator:navigator,favorites:favorites) }
            else { entryForm }
        }
        .onDisappear { cancel() }
        .onAppear {
            if automaticallyResolve,!resolvedInitialInput {
                resolvedInitialInput = true; resolve()
            }
            #if DEBUG && targetEnvironment(simulator)
            let preview = ProcessInfo.processInfo.environment["HUASIDELOAD_UI_PREVIEW"]
            if preview == "place-link" {
                input = "https://www.google.com/maps/search/?api=1&query=10.779783,106.699018"
            }
            if preview == "place-link-preview" {
                pin = SelectedMapPin(coordinate:.init(latitude:10.779783,longitude:106.699018),
                    name:"Bưu điện Trung tâm Sài Gòn",title:"Địa điểm từ Google Maps")
            }
            #endif
        }
    }

    private var entryForm: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Chuyển địa điểm từ Google Maps",systemImage:"map.fill").font(.headline)
                    Text("Trong Google Maps, chọn địa điểm → Chia sẻ → HuaSideload, rồi mở app để nhận ghim. Bạn cũng có thể sao chép liên kết và dán bên dưới.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    TextField("https://maps.app.goo.gl/…",text:$input,axis:.vertical)
                        .lineLimit(3...6).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL).accessibilityIdentifier("place-link-input")
                        .onChange(of:input) { _,_ in cancel(); results = []; message = "" }
                    PasteButton(payloadType:String.self) { values in
                        if let first = values.first { input = first }
                    }.accessibilityLabel("Dán liên kết địa điểm")
                    Button(action:resolve) {
                        HStack {
                            if loading { ProgressView() }
                            Label(loading ? "Đang đọc địa điểm…" : "Xem địa điểm",systemImage:"mappin.and.ellipse")
                        }
                    }.disabled(loading || input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("place-link-resolve")
                    if loading { Button("Hủy tìm",role:.cancel) { cancel() } }
                } header: { Text("Liên kết địa điểm") } footer: {
                    Text("Link rút gọn cần mạng để mở. Link có mã địa điểm sẽ được đối chiếu để lấy ghim Google Maps. Kiểm tra ghim trước khi chọn dẫn đường hoặc lưu yêu thích.")
                }
                if !message.isEmpty {
                    Section { Text(message).font(.callout).foregroundStyle(isError ? Color.red : Color.secondary) }
                }
                if !results.isEmpty {
                    Section("Chọn đúng địa điểm") {
                        ForEach(results) { place in
                            Button {
                                showPin(place.item.placemark.coordinate,name:place.name)
                            } label: {
                                VStack(alignment:.leading,spacing:4) {
                                    Text(place.name).font(.headline).foregroundStyle(.primary)
                                    Text(place.address).font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical,4)
                            }.accessibilityIdentifier("place-link-search-result")
                        }
                    }
                }
            }
            .navigationTitle("Dán link địa điểm").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Hủy") { cancel(); dismiss() } } }
        }
    }

    private func cancel() {
        requestID = UUID(); operation?.cancel(); operation = nil
        search?.cancel(); search = nil; loading = false
    }
    private func showPin(_ coordinate: CLLocationCoordinate2D,name: String?) {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            message = "Địa điểm trả về có tọa độ không hợp lệ."; isError = true; return
        }
        let name = name?.trimmingCharacters(in:.whitespacesAndNewlines)
        pin = SelectedMapPin(coordinate:coordinate,name:String((name?.isEmpty == false ? name! : "Điểm từ Google Maps").prefix(60)),
            title:"Địa điểm từ Google Maps")
    }
    private func resolve() {
        cancel(); let id = UUID(); requestID = id
        loading = true; isError = false; message = ""; results = []
        let text = input
        operation = Task { @MainActor in
            defer { if requestID == id { loading = false; operation = nil; search = nil } }
            do {
                let target = try await MapPlaceLinkResolver().resolve(text)
                try Task.checkCancellation()
                guard requestID == id else { return }
                switch target {
                case let .coordinate(point,name):
                    showPin(.init(latitude:point.latitude,longitude:point.longitude),name:name)
                case let .search(query):
                    let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
                    let search = MKLocalSearch(request:request); self.search = search
                    let response = try await search.start()
                    try Task.checkCancellation()
                    guard requestID == id else { return }
                    results = response.mapItems.filter { CLLocationCoordinate2DIsValid($0.placemark.coordinate) }
                        .prefix(8).map { .init(item:$0) }
                    message = results.isEmpty ? "Chưa tìm được địa điểm theo tên/địa chỉ trong link. Thử tìm bằng tên cụ thể hơn."
                        : "Link chỉ có tên/địa chỉ. Chọn đúng kết quả rồi kiểm tra ghim trên bản đồ."
                    isError = results.isEmpty
                }
            } catch is CancellationError { }
            catch {
                guard requestID == id,!Task.isCancelled else { return }
                message = (error as? MapPlaceLink.LinkError)?.localizedDescription ?? "Chưa tìm được địa điểm. Kiểm tra mạng hoặc thử liên kết khác."
                isError = true
            }
        }
    }
}
