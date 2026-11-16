import Combine
import MapKit

@MainActor
final class DestinationSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable {
        let title: String
        let subtitle: String
        let completion: MKLocalSearchCompletion?
        var id: String { title+"\n"+subtitle }
    }
    enum Phase { case idle, suggesting, suggestions, searching, results, resolving, failed }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var results: [RouteNavigator.Destination] = []
    @Published private(set) var selected: SelectedMapPin?
    @Published private(set) var message = ""
    private var revision = UUID()
    private var debounce: Task<Void,Never>?
    private var requestTask: Task<Void,Never>?
    private var suggestionTimeout: Task<Void,Never>?
    private var completer: MKLocalSearchCompleter?
    private var operation: MKLocalSearch?
    var busy: Bool { phase == .suggesting || phase == .searching || phase == .resolving }

    func cancel() {
        revision = UUID()
        debounce?.cancel(); debounce = nil
        completer?.delegate = nil; completer?.cancel(); completer = nil
        operation?.cancel(); operation = nil
        requestTask?.cancel(); requestTask = nil
        suggestionTimeout?.cancel(); suggestionTimeout = nil
    }

    func edit(_ text: String, region: MKCoordinateRegion?) {
        cancel(); selected = nil; suggestions = []; results = []; message = ""
        let query = String(text.trimmingCharacters(in:.whitespacesAndNewlines).prefix(200))
        guard !query.isEmpty else { phase = .idle; return }
        phase = .suggesting
        let token = revision
        debounce = Task {
            do { try await Task.sleep(for:.milliseconds(350)) } catch { return }
            guard token == revision,!Task.isCancelled else { return }
            // A new instance isolates callbacks belonging to an older query.
            let source = MKLocalSearchCompleter(); source.delegate = self
            source.resultTypes = [.address,.pointOfInterest,.query]
            if let region { source.region = region }
            completer = source; source.queryFragment = query
            suggestionTimeout = Task {
                do { try await Task.sleep(for:.seconds(12)) } catch { return }
                guard revision == token,completer === source,phase == .suggesting else { return }
                source.delegate = nil; source.cancel(); completer = nil
                phase = .failed; message = "Gợi ý phản hồi chậm. Bấm Enter để tìm hoặc kiểm tra mạng."
            }
        }
    }

    func completerDidUpdateResults(_ source: MKLocalSearchCompleter) {
        guard completer === source,phase == .suggesting || phase == .suggestions else { return }
        suggestionTimeout?.cancel(); suggestionTimeout = nil
        var seen = Set<String>()
        suggestions = source.results.compactMap { value -> Suggestion? in
            let item = Suggestion(title:value.title,subtitle:value.subtitle,completion:value)
            return seen.insert(item.id).inserted ? item : nil
        }.prefix(10).map { $0 }
        phase = .suggestions
        message = suggestions.isEmpty ? "Chưa có gợi ý. Bấm Enter để tìm theo nội dung đã nhập." : ""
    }

    func completer(_ source: MKLocalSearchCompleter,didFailWithError error: Error) {
        guard completer === source else { return }
        suggestionTimeout?.cancel(); suggestionTimeout = nil
        phase = .failed; suggestions = []
        message = "Chưa tải được gợi ý. Kiểm tra mạng hoặc bấm Enter để tìm lại."
    }

    func submit(_ text: String, region: MKCoordinateRegion?) {
        let query = String(text.trimmingCharacters(in:.whitespacesAndNewlines).prefix(200))
        guard !query.isEmpty else { edit("",region:region); return }
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
        if let region { request.region = region }
        run(request,resolveSelection:false)
    }

    func resolve(_ item: Suggestion, region: MKCoordinateRegion?) {
        guard let completion = item.completion else { return }
        let request = MKLocalSearch.Request(completion:completion)
        if let region { request.region = region }
        run(request,resolveSelection:true)
    }

    private func run(_ request: MKLocalSearch.Request,resolveSelection: Bool) {
        cancel(); suggestions = []; results = []; selected = nil; message = ""
        phase = resolveSelection ? .resolving : .searching
        let token = revision, search = MKLocalSearch(request:request)
        operation = search
        requestTask = Task {
            do {
                let response = try await search.start()
                guard token == revision,!Task.isCancelled else { return }
                let places = response.mapItems.filter { CLLocationCoordinate2DIsValid($0.placemark.coordinate) }
                    .map { RouteNavigator.Destination(item:$0) }
                // Query suggestions can represent categories. Keep a choice list
                // when resolving one returns several possible places.
                if resolveSelection,places.count == 1,let place = places.first { results = places; choose(place) }
                else {
                    results = places; phase = .results
                    message = places.isEmpty ? "Không tìm thấy địa điểm. Thử thêm tên đường hoặc khu vực." : ""
                }
            } catch {
                guard token == revision,!Task.isCancelled else { return }
                phase = .failed; message = "Chưa tìm được địa điểm. Kiểm tra mạng rồi bấm Enter để thử lại."
            }
            if token == revision { operation = nil; requestTask = nil }
        }
    }

    func choose(_ place: RouteNavigator.Destination) {
        cancel()
        selected = SelectedMapPin(coordinate:place.item.placemark.coordinate,name:place.name,title:"Xem địa điểm")
        phase = .results
    }

    func backToResults() { selected = nil }

    #if DEBUG && targetEnvironment(simulator)
    func prepareVisualPreview(_ kind: String) {
        cancel(); phase = kind == "search-suggestions" ? .suggestions : .results
        suggestions = [Suggestion(title:"Bưu điện Trung tâm Sài Gòn",subtitle:"2 Công xã Paris, Bến Nghé, Thành phố Hồ Chí Minh",completion:nil),
            .init(title:"Bưu điện Quận 1",subtitle:"Thành phố Hồ Chí Minh",completion:nil),
            .init(title:"Bưu điện Thành phố Thủ Đức",subtitle:"Thành phố Hồ Chí Minh",completion:nil)]
        let item = MKMapItem(placemark:MKPlacemark(coordinate:.init(latitude:10.779783,longitude:106.699018)))
        item.name = "Bưu điện Trung tâm Sài Gòn"
        results = [.init(item:item)]
        if kind == "search-preview" { choose(results[0]) }
    }
    #endif
}
