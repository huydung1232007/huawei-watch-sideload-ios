import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
final class RouteNavigator: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Mode: String, CaseIterable, Identifiable {
        case motorcycle, walking, driving
        var id: String { rawValue }
        var title: String { switch self { case .motorcycle: return "Xe máy"; case .walking: return "Đi bộ"; case .driving: return "Ô tô" } }
        var transport: MKDirectionsTransportType { self == .walking ? .walking : .automobile }
    }
    struct Destination: Identifiable {
        let id = UUID()
        let item: MKMapItem
        var name: String { item.name ?? "Điểm đến" }
        var address: String { item.placemark.title ?? name }
    }
    private struct Maneuver {
        let at: Double
        let instruction: String
        let turn: PineNavigationWire.Turn
    }

    @Published var query = ""
    @Published var mode: Mode = .motorcycle { didSet { if mode != oldValue { clearPlan() } } }
    @Published private(set) var results: [Destination] = []
    @Published private(set) var destination: Destination?
    @Published private(set) var locationStatus = "Chưa lấy vị trí."
    @Published private(set) var status = "Chọn điểm đến và xem tuyến đường trước khi bắt đầu."
    @Published private(set) var preview = ""
    @Published private(set) var instruction = ""
    @Published private(set) var distanceToTurn = ""
    @Published private(set) var isSearching = false
    @Published private(set) var isCalculating = false
    @Published private(set) var isNavigating = false
    @Published private(set) var hasLocation = false
    @Published private(set) var hasRoute = false
    @Published private(set) var displayPolyline: MKPolyline?
    @Published private(set) var routeRevision = UUID()
    @Published private(set) var instructionPreview: [String] = []

    var onGuidance: (([UInt8]) -> Void)?
    var onStop: (() -> Void)?
    private let manager = CLLocationManager()
    private var waitingForLocation = false
    private var currentLocation: CLLocation?
    private var search: MKLocalSearch?
    private var directions: MKDirections?
    private struct Plan { let polyline: MKPolyline; let distance: Double; let expectedTravelTime: Double }
    private var route: Plan?
    private var motorcycleTask: Task<Void, Never>?
    private var motorcycleRequestID = UUID()
    private var lastMotorcycleRequest = Date.distantPast
    private var routeOrigin: CLLocation?
    private var backgroundActivity: CLBackgroundActivitySession?
    private var fixMonitor: Task<Void, Never>?
    private var path: RouteProgress?
    private var maneuvers: [Maneuver] = []
    private var maneuverIndex = 0
    private var progress = 0.0
    private var lastFixTime: Date?
    private var lastSent = Date.distantPast
    private var lastSentIndex = -1

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
    }

    func requestLocation() {
        waitingForLocation = true
        switch manager.authorizationStatus {
        case .notDetermined:
            locationStatus = "Chọn cho phép vị trí trên iPhone."
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationStatus = "Đang lấy vị trí GPS…"
            manager.requestLocation()
        default:
            waitingForLocation = false
            locationStatus = "Ứng dụng cần quyền vị trí và Vị trí chính xác để tính tuyến."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isNavigating && ![.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) {
            stop(reason: "Quyền vị trí không còn được cấp.")
        }
        guard waitingForLocation else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted:
            waitingForLocation = false
            locationStatus = "Chưa được cấp quyền vị trí."
        default: break
        }
    }

    func searchDestination() {
        guard !isNavigating else { return }
        let text = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !text.isEmpty else { return }
        search?.cancel()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let location = currentLocation {
            request.region = MKCoordinateRegion(center: location.coordinate,
                latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        }
        let operation = MKLocalSearch(request: request)
        search = operation
        isSearching = true
        status = "Đang tìm điểm đến…"
        Task {
            do {
                let response = try await operation.start()
                guard self.search === operation else { return }
                self.results = response.mapItems.prefix(8).map { Destination(item: $0) }
                self.status = self.results.isEmpty ? "Không tìm thấy. Thử tên hoặc địa chỉ cụ thể hơn." : "Chọn đúng địa chỉ trong kết quả."
            } catch {
                guard self.search === operation else { return }
                self.status = "Không tìm được địa điểm: \(error.localizedDescription)"
            }
            if self.search === operation { self.isSearching = false }
        }
    }

    func select(_ value: Destination) {
        clearPlan()
        destination = value
        results = []
        status = "Đã chọn \(value.name). Bấm Tính tuyến đường."
    }

    func clearPlan() {
        stop(notifyWatch: true)
        directions?.cancel()
        motorcycleRequestID = UUID(); motorcycleTask?.cancel(); motorcycleTask = nil
        directions = nil
        isCalculating = false
        route = nil; path = nil; maneuvers = []
        hasRoute = false; displayPolyline = nil; instructionPreview = []; routeOrigin = nil
        preview = ""; instruction = ""; distanceToTurn = ""
    }

    func calculateRoute() {
        guard !isNavigating, let destination else { return }
        guard let location = currentLocation, Date().timeIntervalSince(location.timestamp) < 120,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 80 else {
            requestLocation()
            status = "Lấy vị trí GPS chính xác rồi bấm Tính tuyến đường."
            return
        }
        directions?.cancel()
        motorcycleRequestID = UUID(); motorcycleTask?.cancel(); motorcycleTask = nil
        if mode == .motorcycle {
            calculateMotorcycleRoute(from: location, to: destination)
            return
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = destination.item
        request.transportType = mode.transport
        request.requestsAlternateRoutes = false
        let operation = MKDirections(request: request)
        directions = operation
        isCalculating = true
        hasRoute = false
        displayPolyline = nil
        instructionPreview = []
        status = "Đang tính tuyến đường bằng Apple Maps…"
        Task {
            do {
                let response = try await operation.calculate()
                guard self.directions === operation else { return }
                guard let route = response.routes.first else { throw RouteError.noRoute }
                try self.prepare(route)
                self.routeOrigin = location
                self.status = "Kiểm tra điểm đến và tuyến đường, rồi bấm Bắt đầu."
            } catch {
                guard self.directions === operation else { return }
                self.status = "Không tính được tuyến đường: \(error.localizedDescription)"
            }
            if self.directions === operation { self.isCalculating = false }
        }
    }

    private enum RouteError: LocalizedError {
        case noRoute
        var errorDescription: String? { "Apple Maps không trả về tuyến đường phù hợp tại khu vực này." }
    }

    private func prepare(_ route: MKRoute) throws {
        let mapPoints = (0..<route.polyline.pointCount).map { route.polyline.points()[$0] }
        guard mapPoints.count >= 2 else { throw RouteError.noRoute }
        let lengths = zip(mapPoints, mapPoints.dropFirst()).map { $0.0.distance(to: $0.1) }
        guard let path = RouteProgress(points: mapPoints.map { .init(x: $0.x, y: $0.y) }, lengths: lengths) else { throw RouteError.noRoute }
        let stepDistance = route.steps.reduce(0.0) { $0 + max(0, $1.distance) }
        let scale = path.totalLength / max(1, stepDistance)
        var along = 0.0
        var turns: [Maneuver] = []
        for step in route.steps {
            let text = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                turns.append(Maneuver(at: along * scale, instruction: text, turn: RouteInstruction.turn(for: text)))
            }
            along += max(0, step.distance)
        }
        if let last = turns.last, last.at >= path.totalLength - 5 { turns.removeLast() }
        turns.append(Maneuver(at: path.totalLength, instruction: "Đến " + (destination?.name ?? "điểm đến"), turn: .destination))
        self.route = Plan(polyline: route.polyline, distance: route.distance, expectedTravelTime: route.expectedTravelTime); self.path = path; maneuvers = turns
        displayPolyline = route.polyline; routeRevision = UUID()
        instructionPreview = turns.map(\.instruction)
        preview = "\(Self.distance(route.distance)) · khoảng \(max(1, Int(ceil(route.expectedTravelTime / 60)))) phút · \(mode.title)"
        hasRoute = true
    }

    private func calculateMotorcycleRoute(from location: CLLocation, to destination: Destination) {
        guard Date().timeIntervalSince(lastMotorcycleRequest) >= 3 else {
            status = "Đợi vài giây trước khi tính lại tuyến xe máy."
            return
        }
        let target = destination.item.placemark.coordinate
        guard location.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)) < 100_000 else {
            status = "Bản thử máy chủ công cộng chỉ hỗ trợ điểm đến cách dưới 100 km."
            return
        }
        lastMotorcycleRequest = Date()
        let requestID = UUID(); motorcycleRequestID = requestID
        isCalculating = true; hasRoute = false; displayPolyline = nil; instructionPreview = []
        status = "Đang tính tuyến xe máy bằng Valhalla/OpenStreetMap…"
        motorcycleTask = Task {
            do {
                var request = URLRequest(url: URL(string: "https://valhalla1.openstreetmap.de/route")!)
                request.httpMethod = "POST"; request.timeoutInterval = 30
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("github.com/huydung1232007/huawei-watch-sideload-ios-personal-test", forHTTPHeaderField: "X-Client-Id")
                request.httpBody = try MotorcycleRoute.request(
                    origin: .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                    destination: .init(latitude: target.latitude, longitude: target.longitude))
                let client = URLSession(configuration: .ephemeral)
                defer { client.invalidateAndCancel() }
                let (data, response) = try await client.data(for: request)
                guard self.motorcycleRequestID == requestID, !Task.isCancelled else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MotorcycleRoute.RouteError.provider("Máy chủ chưa sẵn sàng. Thử lại sau.") }
                let result = try MotorcycleRoute.decode(data)
                let coordinates = result.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                let points = (0..<polyline.pointCount).map { polyline.points()[$0] }
                let lengths = zip(points, points.dropFirst()).map { $0.0.distance(to: $0.1) }
                guard let path = RouteProgress(points: points.map { .init(x: $0.x, y: $0.y) }, lengths: lengths) else { throw RouteError.noRoute }
                self.route = Plan(polyline: polyline, distance: result.distance, expectedTravelTime: result.duration)
                self.path = path
                self.maneuvers = result.steps.map { Maneuver(at: path.cumulative[$0.index], instruction: $0.instruction, turn: $0.turn) }
                self.routeOrigin = location
                self.displayPolyline = polyline; self.routeRevision = UUID()
                self.instructionPreview = self.maneuvers.map(\.instruction)
                self.preview = "\(Self.distance(result.distance)) · khoảng \(max(1, Int(ceil(result.duration / 60)))) phút · Xe máy · OSM"
                self.hasRoute = true
                self.status = "Kiểm tra tuyến xe máy và điểm đến, rồi bấm Bắt đầu."
            } catch {
                guard self.motorcycleRequestID == requestID else { return }
                self.status = "Không tính được tuyến xe máy: \(error.localizedDescription)"
            }
            if self.motorcycleRequestID == requestID { self.isCalculating = false }
        }
    }

    func start() {
        guard hasRoute, path != nil, !maneuvers.isEmpty, !isNavigating else { return }
        guard let location = currentLocation, Date().timeIntervalSince(location.timestamp) < 60 else {
            requestLocation()
            status = "Đang lấy vị trí mới. Khi có GPS, bấm Bắt đầu lại."
            return
        }
        guard [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) else { requestLocation(); return }
        guard location.horizontalAccuracy <= 60, let routeOrigin,
              location.distance(from: routeOrigin) < 60 else {
            hasRoute = false
            status = "Vị trí đã thay đổi hoặc GPS chưa chính xác. Lấy vị trí và tính lại tuyến trước khi bắt đầu."
            return
        }
        maneuverIndex = 0; progress = 0; lastFixTime = nil
        lastSent = .distantPast; lastSentIndex = -1
        isNavigating = true
        manager.activityType = mode == .walking ? .fitness : .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.distanceFilter = kCLDistanceFilterNone
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        backgroundActivity = CLBackgroundActivitySession()
        manager.startUpdatingLocation()
        fixMonitor?.cancel()
        fixMonitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.isNavigating else { return }
                if Date().timeIntervalSince(self.currentLocation?.timestamp ?? .distantPast) > 25 {
                    self.status = "Mất tín hiệu GPS; đang chờ vị trí mới."
                    self.emit(instruction: "Mất GPS - chờ vị trí mới", distance: "", turn: .unspecified, force: true)
                }
            }
        }
        updateGuidance(location, force: true)
    }

    func stop(reason: String = "Đã dừng điều hướng.", notifyWatch: Bool = true) {
        let wasNavigating = isNavigating
        isNavigating = false
        manager.stopUpdatingLocation()
        backgroundActivity?.invalidate()
        backgroundActivity = nil
        fixMonitor?.cancel(); fixMonitor = nil
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
        manager.distanceFilter = 5
        if wasNavigating {
            status = reason
            if notifyWatch { onStop?() }
        }
    }

    func deliveryFailed(_ message: String) {
        stop(reason: "Đã dừng vì không gửi được chỉ dẫn tới đồng hồ: \(message)", notifyWatch: false)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              abs(Date().timeIntervalSince(location.timestamp)) < 30 else { return }
        currentLocation = location
        waitingForLocation = false
        hasLocation = location.horizontalAccuracy <= 80
        locationStatus = "GPS: sai số khoảng \(Int(location.horizontalAccuracy)) m."
        if !hasLocation { locationStatus += " Cần Vị trí chính xác và tín hiệu GPS tốt hơn." }
        if isNavigating { updateGuidance(location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        waitingForLocation = false
        locationStatus = "Chưa lấy được GPS: \(error.localizedDescription)"
        if (error as? CLError)?.code == .denied { stop(reason: "Quyền vị trí không còn được cấp.") }
        else if isNavigating {
            emit(instruction: "Đang chờ GPS chính xác", distance: "", turn: .unspecified, force: true)
        }
    }

    private func updateGuidance(_ location: CLLocation, force: Bool = false) {
        guard isNavigating, let path, let route, !maneuvers.isEmpty else { return }
        guard location.horizontalAccuracy <= 60 else {
            status = "GPS chưa đủ chính xác; đang chờ tín hiệu tốt hơn."
            emit(instruction: "Đang chờ GPS chính xác", distance: "", turn: .unspecified, force: force)
            return
        }
        let point = MKMapPoint(location.coordinate)
        let elapsed = max(1, min(120, lastFixTime.map { location.timestamp.timeIntervalSince($0) } ?? 1))
        let speed = max(location.speed, mode == .walking ? 2 : 15)
        let window = max(300, elapsed * speed * 2.5 + 50)
        guard let projection = path.project(.init(x: point.x, y: point.y),
            minimum: max(0, progress - 35), maximum: min(path.totalLength, progress + window), preferred: progress) else { return }
        guard projection.crossTrack <= (mode == .walking ? 55 : 90) else {
            status = "Bạn đang lệch tuyến. Dừng và tính lại tuyến từ vị trí hiện tại."
            emit(instruction: "Lệch tuyến - xem iPhone", distance: "", turn: .unspecified, force: force)
            return
        }
        progress = projection.along
        lastFixTime = location.timestamp
        let advance = mode == .walking ? 8.0 : 15.0
        while maneuverIndex + 1 < maneuvers.count, progress > maneuvers[maneuverIndex].at + advance { maneuverIndex += 1 }
        let next = maneuvers[maneuverIndex]
        let remaining = max(0, next.at - progress)
        let totalRemaining = max(0, path.totalLength - progress)
        if totalRemaining < 25, location.horizontalAccuracy <= 25, let destination,
           location.distance(from: CLLocation(latitude: destination.item.placemark.coordinate.latitude,
                                              longitude: destination.item.placemark.coordinate.longitude)) < 25 {
            emit(instruction: "Đã đến " + destination.name, distance: "0 m", turn: .destination, force: true)
            stop(reason: "Đã đến điểm đến.", notifyWatch: false)
            return
        }
        status = "Đang điều hướng · còn \(Self.distance(totalRemaining))"
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        let eta = formatter.string(from: Date().addingTimeInterval(route.expectedTravelTime * totalRemaining / path.totalLength)) + ";ETA;;"
        let currentSpeed = location.speed >= 0 ? String(format: "%.0f;km/h", location.speed * 3.6) : ""
        emit(instruction: next.instruction, distance: Self.distance(remaining), turn: next.turn,
             eta: eta, speed: currentSpeed, force: force)
    }

    private func emit(instruction: String, distance: String, turn: PineNavigationWire.Turn,
                      eta: String = "", speed: String = "", force: Bool) {
        guard force || lastSentIndex != maneuverIndex || Date().timeIntervalSince(lastSent) >= 3 else { return }
        self.instruction = instruction; distanceToTurn = distance
        do {
            let data = try PineNavigationWire.guidance(instruction: instruction, distance: distance, turn: turn, eta: eta, speed: speed)
            lastSent = Date(); lastSentIndex = maneuverIndex
            onGuidance?(data)
        } catch { status = "Không mã hóa được chỉ dẫn: \(error)" }
    }

    private static func distance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(max(0, Int((meters / 5).rounded()) * 5)) m"
    }

}
