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
    struct RouteChoice: Identifiable {
        let id: UUID
        let title: String
        let detail: String
        let via: String
        let polyline: MKPolyline
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
    @Published private(set) var currentTurn: PineNavigationWire.Turn = .unspecified
    @Published private(set) var distanceToTurn = ""
    @Published private(set) var followUpInstruction = ""
    @Published private(set) var remainingTripSummary = ""
    @Published private(set) var directionState: RouteDirectionPolicy.State = .unavailable
    @Published private(set) var isCheckingDeparture = false
    var isOppositeDirection: Bool { directionCheckEnabled && directionState == .opposite }
    var directionStatus: String {
        guard directionCheckEnabled else { return "Kiểm tra hướng di chuyển: đã tắt." }
        switch directionState {
        case .opposite: return "Đang đi ngược hướng tuyến. Kiểm tra bản đồ."
        case .following: return "Hướng di chuyển phù hợp tuyến."
        case .checking: return "Đang xác nhận hướng di chuyển GPS."
        case .unavailable: return "Chưa đủ dữ liệu hướng di chuyển GPS."
        }
    }
    @Published var directionCheckEnabled = UserDefaults.standard.object(forKey:"routeDirectionCheckV1") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(directionCheckEnabled,forKey:"routeDirectionCheckV1")
            clearDirectionObservation()
            if let fix = currentLocation { updateGuidance(fix,force:true) }
        }
    }
    @Published var followingManeuverEnabled = UserDefaults.standard.object(forKey:"watchFollowingManeuverV1") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(followingManeuverEnabled,forKey:"watchFollowingManeuverV1")
            if !followingManeuverEnabled { followingManeuverPolicy.reset() }
            if let fix = currentLocation { updateGuidance(fix,force:true) }
        }
    }
    @Published var chainedTurnsEnabled = UserDefaults.standard.object(forKey:"watchChainedTurnsV1") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(chainedTurnsEnabled,forKey:"watchChainedTurnsV1")
            if let fix = currentLocation { updateGuidance(fix,force:true) }
        }
    }
    @Published var watchTripInfoEnabled = UserDefaults.standard.object(forKey:"watchTripInfoV1") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(watchTripInfoEnabled,forKey:"watchTripInfoV1")
            if let fix = currentLocation { updateGuidance(fix,force:true) }
        }
    }
    @Published private(set) var isSearching = false
    @Published private(set) var isCalculating = false
    @Published private(set) var isNavigating = false
    @Published private(set) var isRerouting = false
    @Published private(set) var liveTrip: TripRecord?
    @Published var turnAlertsEnabled = UserDefaults.standard.object(forKey: "turnAlertsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(turnAlertsEnabled,forKey: "turnAlertsEnabled") }
    }
    @Published var autoRerouteEnabled = UserDefaults.standard.object(forKey: "autoRerouteEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoRerouteEnabled,forKey: "autoRerouteEnabled")
            reroutePolicy.resetObservation()
        }
    }
    let history = TripHistoryStore()
    let favorites = FavoritePlacesStore()
    @Published private(set) var isCapturingFavorite = false
    @Published private(set) var capturedFavorite: FavoritePlace?
    @Published private(set) var favoriteCaptureError: String?
    private var favoriteTimeout: Task<Void,Never>?
    @Published private(set) var hasLocation = false
    @Published private(set) var hasRoute = false
    @Published private(set) var displayPolyline: MKPolyline?
    @Published private(set) var routeChoices: [RouteChoice] = []
    @Published private(set) var selectedRouteID: UUID?
    @Published private(set) var routeRevision = UUID()
    @Published private(set) var instructionPreview: [String] = []

    var onGuidance: (([UInt8], Bool) -> Void)?
    var onRouteReset: (() -> Void)?
    var onStop: (() -> Void)?
    private let manager = CLLocationManager()
    private var waitingForLocation = false
    private var currentLocation: CLLocation?
    private var search: MKLocalSearch?
    private var directions: MKDirections?
    private struct Plan { let polyline: MKPolyline; let distance: Double; let expectedTravelTime: Double }
    private struct PreparedRoute {
        let id = UUID()
        let plan: Plan
        let path: RouteProgress
        let maneuvers: [Maneuver]
        let origin: CLLocation
        let name: String
    }
    private var preparedRoutes: [PreparedRoute] = []
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
    private var refreshPolicy = GuidanceRefreshPolicy()
    private var alertPolicy = TurnAlertPolicy()
    private var followingManeuverPolicy = FollowingManeuverPolicy()
    private var directionPolicy = RouteDirectionPolicy()
    private var reroutePolicy = ReroutePolicy()
    private var tripAccumulator: TripAccumulator?
    private var lastCheckpoint = Date.distantPast
    private var tripStartedAt = Date()
    private var navigationSession = UUID()
    private var rerouteTask: Task<Void,Never>?
    private var rerouteDirections: MKDirections?
    private var calculateWhenLocated = false

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
        if isCapturingFavorite { startFavoriteLocationUpdates() }
        guard waitingForLocation else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted:
            waitingForLocation = false
            locationStatus = "Chưa được cấp quyền vị trí."
        default: break
        }
    }

    func captureFavoriteGPS() {
        guard !isCapturingFavorite else { return }
        capturedFavorite = nil; favoriteCaptureError = nil
        isCapturingFavorite = true
        if let fix = currentLocation, useFavoriteFix(fix) { return }
        startFavoriteLocationUpdates()
        guard isCapturingFavorite else { return }
        favoriteTimeout = Task { [weak self] in
            do { try await Task.sleep(for:.seconds(20)) } catch { return }
            guard let self, self.isCapturingFavorite else { return }
            self.cancelFavoriteGPS()
            self.favoriteCaptureError = "Chưa lấy được GPS đủ chính xác. Bật Vị trí chính xác, ra nơi thoáng rồi thử lại."
        }
    }

    private func startFavoriteLocationUpdates() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if !isNavigating {
                manager.distanceFilter = kCLDistanceFilterNone
                manager.startUpdatingLocation()
            }
        default:
            cancelFavoriteGPS()
            favoriteCaptureError = "Cần cho phép Vị trí và bật Vị trí chính xác để lưu GPS hiện tại."
        }
    }

    @discardableResult private func useFavoriteFix(_ fix: CLLocation) -> Bool {
        guard isCapturingFavorite,
              FavoriteGPSFix.usable(timestamp:fix.timestamp.timeIntervalSinceReferenceDate,
                  now:Date().timeIntervalSinceReferenceDate,accuracy:fix.horizontalAccuracy) else { return false }
        capturedFavorite = FavoritePlace(name:"Vị trí hiện tại",latitude:fix.coordinate.latitude,longitude:fix.coordinate.longitude)
        cancelFavoriteGPS()
        return true
    }

    func cancelFavoriteGPS() {
        guard isCapturingFavorite else { return }
        isCapturingFavorite = false; favoriteTimeout?.cancel(); favoriteTimeout = nil
        if !isNavigating { manager.stopUpdatingLocation(); manager.distanceFilter = 5 }
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

    func selectAndCalculate(_ value: Destination) {
        select(value)
        if let fix = currentLocation, Date().timeIntervalSince(fix.timestamp) < 60, fix.horizontalAccuracy <= 60 {
            calculateRoute()
        } else {
            calculateWhenLocated = true
            requestLocation()
            status = "Đang lấy vị trí để tính tuyến…"
        }
    }

    func clearPlan() {
        calculateWhenLocated = false
        stop(notifyWatch: true)
        directions?.cancel()
        motorcycleRequestID = UUID(); motorcycleTask?.cancel(); motorcycleTask = nil
        directions = nil
        isCalculating = false
        discardRoutes()
    }

    private func discardRoutes() {
        clearDirectionObservation()
        followingManeuverPolicy.reset()
        route = nil; path = nil; maneuvers = []
        preparedRoutes = []; routeChoices = []; selectedRouteID = nil
        hasRoute = false; displayPolyline = nil; instructionPreview = []; routeOrigin = nil
        preview = ""; instruction = ""; distanceToTurn = ""; followUpInstruction = ""; remainingTripSummary = ""
    }

    private func summary(_ plan: Plan) -> String {
        "\(Self.distance(plan.distance)) · khoảng \(max(1, Int(ceil(plan.expectedTravelTime / 60)))) phút · \(mode.title)"
    }

    private func installRoutes(_ candidates: [PreparedRoute]) throws {
        guard let first = candidates.first else { throw RouteError.noRoute }
        preparedRoutes = candidates
        routeChoices = candidates.enumerated().map { index, candidate in
            RouteChoice(id: candidate.id, title: "Tuyến \(index + 1)", detail: summary(candidate.plan),
                        via: candidate.name, polyline: candidate.plan.polyline)
        }
        applyRoute(first)
        status = candidates.count > 1 ? "Có \(candidates.count) tuyến. Chọn tuyến để xem trên bản đồ, rồi bấm Bắt đầu." : "Chỉ có 1 tuyến phù hợp được trả về. Kiểm tra tuyến rồi bấm Bắt đầu."
    }

    func selectRoute(_ id: UUID) {
        guard !isNavigating, !isCalculating, let candidate = preparedRoutes.first(where: { $0.id == id }) else { return }
        applyRoute(candidate)
        status = "Đã chọn \(routeChoices.first(where: { $0.id == id })?.title ?? "tuyến đường"). Bấm Bắt đầu để đi theo tuyến này."
    }

    private func applyRoute(_ candidate: PreparedRoute) {
        clearDirectionObservation()
        followingManeuverPolicy.reset()
        selectedRouteID = candidate.id
        route = candidate.plan; path = candidate.path; maneuvers = candidate.maneuvers
        routeOrigin = candidate.origin
        displayPolyline = candidate.plan.polyline; routeRevision = UUID()
        instructionPreview = candidate.maneuvers.map(\.instruction)
        preview = summary(candidate.plan)
        instruction = ""; distanceToTurn = ""; followUpInstruction = ""; remainingTripSummary = ""
        maneuverIndex = 0; progress = 0; lastFixTime = nil; refreshPolicy = GuidanceRefreshPolicy()
        hasRoute = true
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
        discardRoutes()
        if mode == .motorcycle {
            calculateMotorcycleRoute(from: location, to: destination)
            return
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = destination.item
        request.transportType = mode.transport
        request.requestsAlternateRoutes = true
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
                let candidates = response.routes.prefix(3).compactMap { try? self.prepare($0, origin: location) }
                try self.installRoutes(candidates)
            } catch {
                guard self.directions === operation else { return }
                self.status = "Không tính được tuyến đường: \(error.localizedDescription)"
            }
            if self.directions === operation { self.isCalculating = false }
        }
    }

    private enum RouteError: LocalizedError {
        case noRoute
        var errorDescription: String? { "Không có tuyến đường phù hợp được trả về tại khu vực này." }
    }

    private func prepare(_ route: MKRoute, origin: CLLocation) throws -> PreparedRoute {
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
        return PreparedRoute(plan: Plan(polyline: route.polyline, distance: route.distance, expectedTravelTime: route.expectedTravelTime),
                             path: path, maneuvers: turns, origin: origin, name: String(route.name.prefix(140)))
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
                let results = try MotorcycleRoute.decodeOptions(data)
                let candidates = results.compactMap { self.prepareMotorcycle($0,origin: location) }
                try self.installRoutes(candidates)
            } catch {
                guard self.motorcycleRequestID == requestID else { return }
                self.status = "Không tính được tuyến xe máy: \(error.localizedDescription)"
            }
            if self.motorcycleRequestID == requestID { self.isCalculating = false }
        }
    }

    private func updateTrip(at time: Date, forceSave: Bool = false) {
        guard let accumulator = tripAccumulator else { return }
        let snapshot = accumulator.snapshot(at: time)
        liveTrip = snapshot
        if forceSave || time.timeIntervalSince(lastCheckpoint) >= 30 {
            history.checkpoint(snapshot); lastCheckpoint = time
        }
    }

    func rerouteManually() {
        reroutePolicy.manualRetry(now: Date().timeIntervalSinceReferenceDate)
        reroute()
    }

    private func reroute() {
        guard isNavigating, !isRerouting, let destination else { return }
        guard let location = currentLocation, Date().timeIntervalSince(location.timestamp) < 15,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35 else {
            status = "Chờ GPS chính xác hơn để tính lại tuyến."
            return
        }
        if mode == .motorcycle && Date().timeIntervalSince(lastMotorcycleRequest) < 3 {
            status = "Đợi vài giây trước khi tính lại tuyến."
            return
        }
        let sessionID = navigationSession
        let transport = mode
        isRerouting = true
        clearDirectionObservation()
        onRouteReset?()
        status = "Đang tính lại tuyến từ vị trí hiện tại…"
        emit(instruction: "Đang tìm tuyến mới…",distance: "",turn: .unspecified,force: true)
        rerouteTask = Task {
            defer {
                if self.navigationSession == sessionID { self.isRerouting = false; self.rerouteTask = nil }
            }
            do {
                let candidates: [PreparedRoute]
                if transport == .motorcycle {
                    guard Date().timeIntervalSince(self.lastMotorcycleRequest) >= 3 else { throw RouteError.noRoute }
                    self.lastMotorcycleRequest = Date()
                    var request = URLRequest(url: URL(string: "https://valhalla1.openstreetmap.de/route")!)
                    request.httpMethod = "POST"; request.timeoutInterval = 30
                    request.setValue("application/json",forHTTPHeaderField: "Content-Type")
                    request.setValue("github.com/huydung1232007/huawei-watch-sideload-ios-personal-test",forHTTPHeaderField: "X-Client-Id")
                    let target = destination.item.placemark.coordinate
                    guard location.distance(from: CLLocation(latitude: target.latitude,longitude: target.longitude)) < 100_000 else { throw RouteError.noRoute }
                    request.httpBody = try MotorcycleRoute.request(
                        origin: .init(latitude: location.coordinate.latitude,longitude: location.coordinate.longitude),
                        destination: .init(latitude: target.latitude,longitude: target.longitude),alternatives: false)
                    let client = URLSession(configuration: .ephemeral)
                    defer { client.invalidateAndCancel() }
                    let (data,response) = try await client.data(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RouteError.noRoute }
                    let results = try MotorcycleRoute.decodeOptions(data)
                    candidates = results.compactMap { self.prepareMotorcycle($0,origin: location) }
                } else {
                    let request = MKDirections.Request()
                    request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
                    request.destination = destination.item
                    request.transportType = transport.transport; request.requestsAlternateRoutes = false
                    let operation = MKDirections(request: request); self.rerouteDirections = operation
                    let response = try await operation.calculate()
                    candidates = response.routes.prefix(1).compactMap { try? self.prepare($0,origin: location) }
                }
                guard self.isNavigating, self.navigationSession == sessionID, !Task.isCancelled else { return }
                try self.installRoutes(candidates)
                self.alertPolicy = TurnAlertPolicy()
                self.reroutePolicy.succeeded(now: Date().timeIntervalSinceReferenceDate)
                self.status = "Đã đổi sang tuyến mới."
                self.isRerouting = false
                if let latest = self.currentLocation { self.updateGuidance(latest,force: true) }
            } catch {
                guard self.isNavigating, self.navigationSession == sessionID, !Task.isCancelled else { return }
                self.reroutePolicy.failed(now: Date().timeIntervalSinceReferenceDate)
                self.status = self.reroutePolicy.needsManualRetry ? "Chưa đổi được tuyến. Mở app và bấm Tính lại tuyến để thử lại." : "Chưa lấy được tuyến mới. Sẽ thử lại khi GPS tốt và có mạng."
                self.emit(instruction: "Chưa có tuyến mới - xem iPhone",distance: "",turn: .unspecified,force: true)
            }
        }
    }

    private func prepareMotorcycle(_ result: MotorcycleRoute, origin: CLLocation) -> PreparedRoute? {
        let coordinates = result.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude,longitude: $0.longitude) }
        let polyline = MKPolyline(coordinates: coordinates,count: coordinates.count)
        let points = (0..<polyline.pointCount).map { polyline.points()[$0] }
        let lengths = zip(points,points.dropFirst()).map { $0.0.distance(to: $0.1) }
        guard let path = RouteProgress(points: points.map { .init(x: $0.x,y: $0.y) },lengths: lengths) else { return nil }
        let turns = result.steps.map { Maneuver(at: path.cumulative[$0.index],instruction: $0.instruction,turn: $0.turn) }
        return PreparedRoute(plan: Plan(polyline: polyline,distance: result.distance,expectedTravelTime: result.duration),
            path: path,maneuvers: turns,origin: origin,name: result.via)
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
        refreshPolicy = GuidanceRefreshPolicy()
        followingManeuverPolicy.reset()
        clearDirectionObservation()
        tripStartedAt = Date(); navigationSession = UUID()
        alertPolicy = TurnAlertPolicy(); reroutePolicy = ReroutePolicy()
        tripAccumulator = TripAccumulator(startedAt: tripStartedAt,destination: destination?.name ?? "Điểm đến",mode: mode.title,walking: mode == .walking)
        updateTrip(at: tripStartedAt,forceSave: true)
        onRouteReset?()
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
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.isNavigating else { return }
                self.updateTrip(at: Date())
                let now = Date()
                if let fix = self.currentLocation {
                    let age = max(0,now.timeIntervalSince(fix.timestamp))
                    self.locationStatus = "GPS: sai số khoảng \(Int(fix.horizontalAccuracy)) m · vị trí cách đây \(Int(age)) giây."
                }
                if !NavigationFixFreshness.isFresh(timestamp: (self.currentLocation?.timestamp ?? .distantPast).timeIntervalSinceReferenceDate,now: now.timeIntervalSinceReferenceDate) {
                    self.clearDirectionObservation()
                    self.reroutePolicy.resetObservation()
                    self.status = "GPS cập nhật chậm; đang chờ vị trí mới."
                    self.emit(instruction: "GPS chậm - chờ vị trí mới", distance: "", turn: .unspecified, force: false)
                }
            }
        }
        updateGuidance(location, force: true)
    }

    func stop(reason: String = "Đã dừng điều hướng.", notifyWatch: Bool = true, outcome: TripRecord.Outcome = .stopped) {
        clearDirectionObservation()
        followingManeuverPolicy.reset()
        let wasNavigating = isNavigating
        isNavigating = false
        navigationSession = UUID(); rerouteTask?.cancel(); rerouteTask = nil
        rerouteDirections?.cancel(); rerouteDirections = nil; isRerouting = false
        if wasNavigating, let accumulator = tripAccumulator {
            let record = accumulator.snapshot(at: Date(),outcome: outcome)
            liveTrip = record; history.finish(record); tripAccumulator = nil
        }
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
        stop(reason: "Đã dừng vì không gửi được chỉ dẫn tới đồng hồ: \(message)", notifyWatch: false, outcome: .interrupted)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.filter({ $0.horizontalAccuracy >= 0 }).max(by: { $0.timestamp < $1.timestamp }),
              NavigationFixFreshness.accepts(timestamp: location.timestamp.timeIntervalSinceReferenceDate,
                  now: Date().timeIntervalSinceReferenceDate,previous: currentLocation?.timestamp.timeIntervalSinceReferenceDate) else { return }
        currentLocation = location
        if isCapturingFavorite { useFavoriteFix(location) }
        waitingForLocation = false
        hasLocation = location.horizontalAccuracy <= 80
        locationStatus = "GPS: sai số khoảng \(Int(location.horizontalAccuracy)) m."
        if !hasLocation { locationStatus += " Cần Vị trí chính xác và tín hiệu GPS tốt hơn." }
        if isNavigating {
            tripAccumulator?.add(.init(time: location.timestamp,latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,accuracy: location.horizontalAccuracy,speed: location.speed))
            updateTrip(at: Date())
            updateGuidance(location)
        } else if calculateWhenLocated && hasLocation {
            calculateWhenLocated = false
            calculateRoute()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        waitingForLocation = false
        locationStatus = "Chưa lấy được GPS: \(error.localizedDescription)"
        if (error as? CLError)?.code == .denied {
            if isCapturingFavorite {
                cancelFavoriteGPS()
                favoriteCaptureError = "Chưa được cấp quyền vị trí. Mở Cài đặt và cho phép vị trí cho app."
            }
            stop(reason: "Quyền vị trí không còn được cấp.")
        }
        else if isNavigating {
            clearDirectionObservation()
            emit(instruction: "Đang chờ GPS chính xác", distance: "", turn: .unspecified, force: true)
        }
    }

    private func clearDirectionObservation() {
        directionPolicy.reset(); directionState = .unavailable; isCheckingDeparture = false
    }

    private func updateGuidance(_ location: CLLocation, force: Bool = false) {
        guard isNavigating, let path, let route, !maneuvers.isEmpty else { return }
        guard NavigationFixFreshness.isFresh(timestamp: location.timestamp.timeIntervalSinceReferenceDate,now: Date().timeIntervalSinceReferenceDate) else {
            clearDirectionObservation()
            reroutePolicy.resetObservation()
            status = "GPS cập nhật chậm; đang chờ vị trí mới."
            emit(instruction: "GPS chậm - chờ vị trí mới",distance: "",turn: .unspecified,force: force)
            return
        }
        guard location.horizontalAccuracy <= 60 else {
            clearDirectionObservation()
            reroutePolicy.resetObservation()
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
        let offRoute = projection.crossTrack > (mode == .walking ? 45 : 70)
        if isRerouting {
            clearDirectionObservation()
            emit(instruction: "Đang tìm tuyến mới…",distance: "",turn: .unspecified,force: force)
            return
        }
        if offRoute {
            clearDirectionObservation()
            let request = autoRerouteEnabled && reroutePolicy.observe(offRoute: true,accuracy: location.horizontalAccuracy,now: Date().timeIntervalSinceReferenceDate)
            status = autoRerouteEnabled ? "Đang xác nhận lệch tuyến…" : "Lệch tuyến. Bấm Tính lại tuyến từ đây."
            if reroutePolicy.needsManualRetry { status = "Chưa đổi được tuyến. Bấm Tính lại tuyến để thử lại." }
            emit(instruction: autoRerouteEnabled ? "Lệch tuyến - chờ tuyến mới" : "Lệch tuyến - xem iPhone",distance: "",turn: .unspecified,force: force)
            if autoRerouteEnabled && request { reroute() }
            return
        }
        reroutePolicy.resetObservation()
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
            stop(reason: "Đã đến điểm đến.", notifyWatch: false, outcome: .completed)
            return
        }
        isCheckingDeparture = false
        if directionCheckEnabled {
            let nearTurn = maneuvers.contains {
                ($0.turn == .left || $0.turn == .right || $0.turn == .uTurn)
                    && abs($0.at-progress) < (mode == .walking ? 18 : 35)
            }
            let bearing = path.stableForwardBearing(at:progress)
            let contextAllowed = totalRemaining > 40 && !nearTurn && bearing != nil
            directionState = directionPolicy.observe(.init(timestamp:location.timestamp.timeIntervalSinceReferenceDate,
                latitude:location.coordinate.latitude,longitude:location.coordinate.longitude,
                accuracy:location.horizontalAccuracy,speed:location.speed,course:location.course,courseAccuracy:location.courseAccuracy),
                now:Date().timeIntervalSinceReferenceDate,routeBearing:bearing,walking:mode == .walking,contextAllowed:contextAllowed)
            if directionState == .opposite {
                followingManeuverPolicy.reset(); remainingTripSummary = ""
                status = "Đang đi ngược hướng tuyến. Kiểm tra hướng trên bản đồ."
                emit(instruction:"Đang đi ngược hướng tuyến; kiểm tra bản đồ",distance:"",turn:.uTurn,force:force)
                return
            }
            let departure = maneuverIndex == 0 && next.at <= 20 && (next.turn == .straight || next.turn == .unspecified)
            if departure && contextAllowed && directionState != .following {
                isCheckingDeparture = true; remainingTripSummary = ""
                status = "Đang chờ đủ chuyển động GPS để xác định hướng khởi hành."
                emit(instruction:"Chờ xác định hướng khởi hành",distance:"",turn:.unspecified,force:force)
                return
            }
        }
        let secondsRemaining = route.expectedTravelTime * totalRemaining / path.totalLength
        remainingTripSummary = WatchGuidancePresentation.summary(meters:totalRemaining,seconds:secondsRemaining) ?? Self.distance(totalRemaining)
        status = "Đang điều hướng · còn \(remainingTripSummary) · ước tính"
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        let eta = WatchGuidancePresentation.arrivalField(clock:formatter.string(from:Date().addingTimeInterval(secondsRemaining)),
            meters:totalRemaining,seconds:secondsRemaining,expanded:watchTripInfoEnabled,
            displayDuration:Int(Date().timeIntervalSinceReferenceDate/5).isMultiple(of:2))
        let following = maneuverIndex+1 < maneuvers.count ? maneuvers[maneuverIndex+1] : nil
        let followUp = chainedTurnsEnabled ? WatchGuidancePresentation.followUp(current:next.turn,remaining:remaining,
            next:following?.turn,gap:following.map { $0.at-next.at }) : ""
        let afterFollowing = maneuverIndex+2 < maneuvers.count ? maneuvers[maneuverIndex+2] : nil
        let showFollowing = followingManeuverPolicy.shouldShow(maneuver:maneuverIndex,current:next.turn,
            remaining:remaining,enabled:followingManeuverEnabled)
        let straightLength: Double?
        if let following,let afterFollowing { straightLength = afterFollowing.at-following.at }
        else { straightLength = nil }
        let currentSpeed = WatchGuidancePresentation.speedField(metersPerSecond:location.speed,
            next:following?.turn,gap:following.map { $0.at-next.at },straightLength:straightLength,showFollowing:showFollowing)
        let vibration = turnAlertsEnabled ? alertPolicy.pattern(maneuver: maneuverIndex,turn: next.turn,distance: remaining,
            elapsed: Date().timeIntervalSince(tripStartedAt),eligible: next.at > 20) : nil
        emit(instruction: next.instruction, distance: Self.distance(remaining), turn: next.turn,
             eta: eta, speed: currentSpeed, force: force || vibration != nil, vibration: vibration ?? "", remainingMeters: remaining,followUp:followUp)
    }

    private func emit(instruction: String, distance: String, turn: PineNavigationWire.Turn,
                      eta: String = "", speed: String = "", force: Bool, vibration: String = "", remainingMeters: Double? = nil,followUp: String = "") {
        self.instruction = instruction; distanceToTurn = distance; currentTurn = turn
        followUpInstruction = followUp
        if turn == .unspecified || turn == .destination {
            remainingTripSummary = ""
            followingManeuverPolicy.reset()
        }
        let watchInstruction = WatchGuidancePresentation.instruction(instruction,followUp:followUp)
        let key = "\(maneuverIndex)|\(turn.rawValue)|\(watchInstruction)"
        guard refreshPolicy.shouldSend(key: key,distance: remainingMeters,now: ProcessInfo.processInfo.systemUptime,force: force) else { return }
        do {
            let data = try PineNavigationWire.guidance(instruction: watchInstruction, distance: distance, turn: turn, eta: eta, speed: speed, vibration: vibration)
            onGuidance?(data,!vibration.isEmpty)
        } catch { status = "Không mã hóa được chỉ dẫn: \(error)" }
    }

    private static func distance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(max(0, Int((meters / 5).rounded()) * 5)) m"
    }

}

#if DEBUG && targetEnvironment(simulator)
extension RouteNavigator {
    // Public-landmark-only data for CI layout screenshots; excluded from device releases.
    func prepareVisualPreview() {
        let end = CLLocationCoordinate2D(latitude: 10.7869,longitude: 106.6981)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: end)); item.name = "Điểm đến minh họa"
        destination = Destination(item: item)
        let paths: [[CLLocationCoordinate2D]] = [
            [.init(latitude:10.77645,longitude:106.70092),.init(latitude:10.7800,longitude:106.6958),.init(latitude:10.7855,longitude:106.6965),end],
            [.init(latitude:10.77645,longitude:106.70092),.init(latitude:10.7802,longitude:106.7022),.init(latitude:10.7870,longitude:106.7000),end],
            [.init(latitude:10.77645,longitude:106.70092),.init(latitude:10.7803,longitude:106.6922),.init(latitude:10.7880,longitude:106.6940),end]
        ]
        let names = ["Nam Kỳ Khởi Nghĩa · Nguyễn Thị Minh Khai","Hai Bà Trưng · Phạm Ngọc Thạch","Pasteur · Võ Thị Sáu"]
        let candidates = paths.enumerated().compactMap { index, coordinates -> PreparedRoute? in
            let line = MKPolyline(coordinates: coordinates,count: coordinates.count)
            let points = coordinates.map { MKMapPoint($0) }
            let lengths = zip(points,points.dropFirst()).map { $0.0.distance(to:$0.1) }
            guard let path = RouteProgress(points: points.map { .init(x:$0.x,y:$0.y) },lengths:lengths) else { return nil }
            return PreparedRoute(plan: Plan(polyline:line,distance:2312+Double(index)*235,expectedTravelTime:420+Double(index)*60),
                path:path,maneuvers:[Maneuver(at:path.totalLength,instruction:"Đến điểm đến",turn:.destination)],
                origin:CLLocation(latitude:10.77645,longitude:106.70092),name:names[index])
        }
        try? installRoutes(candidates)
        currentLocation = CLLocation(latitude:10.77645,longitude:106.70092)
        hasLocation = true; locationStatus = "GPS sẵn sàng"
        history.prepareVisualPreview()
        favorites.prepareVisualPreview()
        let preview = ProcessInfo.processInfo.environment["HUASIDELOAD_UI_PREVIEW"]
        if preview == "guidance" || preview == "direction-warning" {
            instruction = "Rẽ trái vào Nguyễn Trãi"; currentTurn = .left; distanceToTurn = "120 m"
            followUpInstruction = "Sau đó rẽ phải sau 60 m"; remainingTripSummary = "3.2km · 9ph"
            status = "Dữ liệu minh họa · còn 3.2km · khoảng 9 phút"
            liveTrip = TripRecord(id:UUID(),startedAt:Date().addingTimeInterval(-600),endedAt:Date(),
                destination:"Điểm đến minh họa",mode:"Xe máy",distance:2312,outcome:.active)
            isNavigating = true
            if preview == "direction-warning" {
                directionState = .opposite; currentTurn = .uTurn; distanceToTurn = ""
                instruction = "Đang đi ngược hướng tuyến; kiểm tra bản đồ"
                followUpInstruction = ""; remainingTripSummary = ""
                status = "Dữ liệu minh họa · cảnh báo hướng di chuyển"
            }
        }
    }
}
#endif
