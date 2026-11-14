import MapKit
import SwiftUI

struct NavigationHomeView: View {
    @ObservedObject var navigator: RouteNavigator
    @ObservedObject var link: WatchLink
    let connectWatch: () -> Void
    @State private var camera: MapCameraPosition = .automatic
    @State private var searching = false
    @State private var settings = false
    @State private var showingFavorites = false
    @State private var captureFavoriteOnOpen = false
    @State private var selectedPin: SelectedMapPin?

    var body: some View {
        MapReader { proxy in
          Map(position: $camera) {
            if !navigator.isNavigating {
                ForEach(navigator.routeChoices.filter { $0.id != navigator.selectedRouteID }) { choice in
                    MapPolyline(choice.polyline).stroke(.gray.opacity(0.55),lineWidth: 5)
                }
            }
            if let line = navigator.displayPolyline { MapPolyline(line).stroke(.blue,lineWidth: 7) }
            if let place = navigator.destination { Marker(place.name,coordinate: place.item.placemark.coordinate).tint(.orange) }
            UserAnnotation()
          }
          .mapControls { MapCompass(); MapUserLocationButton() }
          .simultaneousGesture(
            LongPressGesture(minimumDuration:0.65,maximumDistance:12)
                .simultaneously(with:DragGesture(minimumDistance:0,coordinateSpace:.local))
                .onEnded { press in
                    guard press.first == true,let touch = press.second,
                          !navigator.isNavigating,!navigator.isCalculating,
                          let coordinate = proxy.convert(touch.startLocation,from:.local),
                          CLLocationCoordinate2DIsValid(coordinate) else { return }
                    selectedPin = SelectedMapPin(coordinate:coordinate)
                }
          )
        }
        .safeAreaInset(edge: .top,spacing: 0) { header }
        .safeAreaInset(edge: .bottom,spacing: 0) { bottomPanel }
        .sheet(isPresented: $searching) { DestinationSearchView(navigator: navigator) }
        .sheet(isPresented: $settings) { NavigationSettingsView(navigator: navigator,link: link) }
        .sheet(isPresented: $showingFavorites) {
            FavoritePlacesView(navigator:navigator,favorites:navigator.favorites,captureOnOpen:captureFavoriteOnOpen)
        }
        .sheet(item:$selectedPin) { pin in
            MapPinDestinationView(pin:pin,navigator:navigator,favorites:navigator.favorites)
        }
        .onAppear {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["HUASIDELOAD_UI_PREVIEW"]?.hasPrefix("favorite") == true { showingFavorites = true }
            if ProcessInfo.processInfo.environment["HUASIDELOAD_UI_PREVIEW"] == "pin" {
                selectedPin = SelectedMapPin(coordinate:.init(latitude:10.77645,longitude:106.70092))
            }
            #endif
        }
        .onChange(of: navigator.routeRevision) { _, _ in
            guard let line = navigator.displayPolyline else { return }
            let rect = line.boundingMapRect
            withAnimation(.easeInOut(duration: 0.5)) {
                if navigator.isNavigating { camera = .userLocation(followsHeading: true,fallback: .automatic) }
                else { camera = .rect(rect.insetBy(dx: -max(1000,rect.width*0.15),dy: -max(1000,rect.height*0.2))) }
            }
        }
        .onChange(of: navigator.isNavigating) { _, active in
            if active { withAnimation { camera = .userLocation(followsHeading: true,fallback: .automatic) } }
        }
    }

    private var header: some View {
        HStack(alignment: .center,spacing: 12) {
            Text("Dẫn đường").font(.system(size: 26,weight: .bold))
            Spacer(minLength: 4)
            Button(action: connectWatch) {
                HStack(spacing: 5) {
                    Image(systemName: "applewatch")
                    if link.isPaired, let battery = link.battery { Text("\(battery)%").font(.caption.bold()) }
                    else { Circle().fill(link.isPaired ? .green : .orange).frame(width: 7,height: 7) }
                }
                .padding(11).background(.regularMaterial,in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(link.isPaired ? "Đồng hồ đã kết nối" : "Kết nối đồng hồ")
            Button { settings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title3).padding(12)
                    .background(.regularMaterial,in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Tùy chọn điều hướng")
        }
        .padding(.horizontal,20).padding(.top,8).padding(.bottom,10)
        .background(.ultraThinMaterial)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading,spacing: 14) {
            if navigator.isNavigating { activePanel }
            else { planningPanel }
            HStack {
                Button {
                    captureFavoriteOnOpen = false; showingFavorites = true
                } label: { Label("Yêu thích",systemImage:"star.fill") }
                Spacer()
                Button {
                    captureFavoriteOnOpen = true; showingFavorites = true
                } label: { Label("Lưu GPS",systemImage:"location.circle") }
            }.font(.subheadline).buttonStyle(.borderless)
            if navigator.mode == .motorcycle {
                Link("Tuyến © OpenStreetMap contributors",destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial,in: RoundedRectangle(cornerRadius: 28,style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.3),lineWidth: 1))
        .shadow(color: .black.opacity(0.12),radius: 18,y: 5)
        .padding(.horizontal,12).padding(.bottom,12)
    }

    private var planningPanel: some View {
        Group {
            Button { searching = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.blue)
                    VStack(alignment: .leading,spacing: 3) {
                        Text(navigator.destination?.name ?? "Bạn muốn đi đâu?")
                            .font(.headline).foregroundStyle(.primary).lineLimit(1)
                        Text(navigator.destination == nil ? "Tìm địa điểm hoặc địa chỉ" : "Chạm để đổi điểm đến")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                }
                .padding(13).background(Color(.secondarySystemGroupedBackground),in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            Label("Nhấn giữ bản đồ để ghim vị trí",systemImage:"hand.tap")
                .font(.caption2).foregroundStyle(.secondary)
            Picker("Phương tiện",selection: $navigator.mode) {
                Label("Xe máy",systemImage: "motorcycle").tag(RouteNavigator.Mode.motorcycle)
                Label("Đi bộ",systemImage: "figure.walk").tag(RouteNavigator.Mode.walking)
                Label("Ô tô",systemImage: "car.fill").tag(RouteNavigator.Mode.driving)
            }
            .pickerStyle(.segmented).disabled(navigator.isCalculating)
            .onChange(of: navigator.mode) { _, _ in if navigator.destination != nil { navigator.calculateRoute() } }

            if navigator.isCalculating {
                HStack { ProgressView(); Text("Đang tìm đường phù hợp…").font(.callout) }.padding(.vertical,8)
            } else if !navigator.routeChoices.isEmpty {
                routeChoices
            }
            Text(navigator.status).font(.caption).foregroundStyle(Color(.secondaryLabel)).lineLimit(1)
            if navigator.hasRoute {
                Button { link.startRouteNavigation() } label: {
                    Label("Bắt đầu hành trình",systemImage: "location.north.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical,9)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16))
                .disabled(!link.isPaired || link.commandsLocked || navigator.isCalculating)
                if !link.isPaired {
                    Button("Kết nối đồng hồ để bắt đầu",action: connectWatch).font(.caption)
                }
            } else if navigator.destination != nil && !navigator.isCalculating {
                Button { navigator.calculateRoute() } label: {
                    Label("Tính tuyến đường",systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .frame(maxWidth: .infinity).padding(.vertical,6)
                }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var routeChoices: some View {
        VStack(alignment: .leading,spacing: 8) {
            HStack {
                Text("Chọn đường đi").font(.subheadline.bold())
                Spacer()
                Text("\(navigator.routeChoices.count) tuyến").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal,showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(navigator.routeChoices) { route in
                        Button { navigator.selectRoute(route.id) } label: {
                            VStack(alignment: .leading,spacing: 6) {
                                HStack {
                                    Text(route.title).font(.subheadline.bold())
                                    Spacer()
                                    Image(systemName: navigator.selectedRouteID == route.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(navigator.selectedRouteID == route.id ? Color.blue : Color.secondary)
                                }
                                Text(route.detail).font(.caption).lineLimit(1)
                                Text(route.via.isEmpty ? "Xem tuyến trên bản đồ" : route.via)
                                    .font(.caption).foregroundStyle(Color(.label).opacity(0.72)).lineLimit(2)
                                    .frame(height: 32,alignment: .topLeading)
                            }
                            .foregroundStyle(.primary).frame(width: 240,alignment: .leading).padding(13)
                            .background(navigator.selectedRouteID == route.id ? Color.blue.opacity(0.09) : Color(.secondarySystemGroupedBackground),in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(navigator.selectedRouteID == route.id ? Color.blue : Color.clear,lineWidth: 1.5))
                        }.buttonStyle(.plain).disabled(link.commandsLocked)
                    }
                }.padding(2)
            }
        }
    }

    private var activePanel: some View {
        Group {
            HStack(alignment: .top,spacing: 14) {
                Image(systemName: turnSymbol).font(.system(size: 34,weight: .bold))
                    .foregroundStyle(.white).frame(width: 68,height: 68)
                    .background(LinearGradient(colors: [.blue,.cyan],startPoint: .topLeading,endPoint: .bottomTrailing),in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading,spacing: 5) {
                    Text(navigator.isRerouting ? "ĐANG ĐỔI TUYẾN" : "TIẾP THEO")
                        .font(.caption2.bold()).tracking(1.3).foregroundStyle(.secondary)
                    Text(navigator.distanceToTurn.isEmpty ? "Đang cập nhật…" : navigator.distanceToTurn)
                        .font(.system(.title,design: .rounded,weight: .bold))
                    Text(navigator.instruction).font(.headline).lineLimit(3)
                    if !navigator.followUpInstruction.isEmpty {
                        Text(navigator.followUpInstruction).font(.subheadline).foregroundStyle(.blue).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            if let trip = navigator.liveTrip {
                HStack {
                    metric(RideFormat.distance(trip.distance),caption: "Đã đi")
                    Spacer()
                    metric(RideFormat.duration(trip.duration),caption: "Thời gian")
                    Spacer()
                    metric(RideFormat.speed(trip.averageSpeed),caption: "TB · km/h")
                }.padding(.vertical,5)
            }
            HStack(spacing: 8) {
                if navigator.isRerouting { ProgressView().controlSize(.small) }
                Text(navigator.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 10) {
                Button { navigator.rerouteManually() } label: {
                    Label("Tính lại",systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical,7)
                }.buttonStyle(.bordered).disabled(navigator.isRerouting)
                Button(role: .destructive) { navigator.stop() } label: {
                    Label("Kết thúc",systemImage: "stop.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical,7)
                }.buttonStyle(.borderedProminent).tint(.red)
            }
        }
    }

    private func metric(_ value: String,caption: String) -> some View {
        VStack(alignment: .leading,spacing: 3) {
            Text(value).font(.system(.headline,design: .rounded))
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var turnSymbol: String {
        switch navigator.currentTurn {
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .uTurn: return "arrow.uturn.down"
        case .destination: return "flag.checkered"
        case .straight: return "arrow.up"
        case .unspecified: return "location.fill"
        }
    }
}

private struct DestinationSearchView: View {
    @ObservedObject var navigator: RouteNavigator
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Tên địa điểm hoặc địa chỉ",text: $navigator.query)
                        .submitLabel(.search).onSubmit { navigator.searchDestination() }
                    Button { navigator.searchDestination() } label: {
                        HStack { if navigator.isSearching { ProgressView() }; Label("Tìm địa điểm",systemImage: "magnifyingglass") }
                    }.disabled(navigator.isSearching || navigator.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section {
                    ForEach(navigator.results) { place in
                        Button {
                            navigator.selectAndCalculate(place); dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(.orange)
                                VStack(alignment: .leading,spacing: 4) {
                                    Text(place.name).font(.headline).foregroundStyle(.primary)
                                    Text(place.address).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical,4)
                        }
                    }
                    if navigator.results.isEmpty { Text(navigator.status).font(.callout).foregroundStyle(.secondary) }
                }
                Section {
                    Button("Lấy vị trí hiện tại") { navigator.requestLocation() }
                    Text(navigator.locationStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Điểm đến").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Xong") { dismiss() } } }
            .task { if !navigator.hasLocation { navigator.requestLocation() } }
        }
    }
}

private struct NavigationSettingsView: View {
    @ObservedObject var navigator: RouteNavigator
    @ObservedObject var link: WatchLink
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Rung nhắc rẽ",isOn: $navigator.turnAlertsEnabled)
                    HStack {
                        Button("Thử rung trái") { link.testTurnHaptic(.left) }
                        Spacer()
                        Button("Thử rung phải") { link.testTurnHaptic(.right) }
                    }.disabled(link.commandsLocked || !link.isPaired)
                } header: { Label("Nhắc rẽ",systemImage: "applewatch.radiowaves.left.and.right") }
                footer: { Text("Nhắc ở khoảng 200 m và 50 m trước chỗ rẽ. Mở Navigation trên đồng hồ để thử. Nếu đồng hồ không rung, bạn có thể tắt tùy chọn này; chỉ dẫn chữ vẫn hoạt động.") }
                Section {
                    Toggle("Tự đổi tuyến khi đi lệch",isOn: $navigator.autoRerouteEnabled)
                } footer: { Text("Chỉ tính lại sau khi GPS đủ chính xác và xác nhận lệch tuyến. Cần mạng để lấy tuyến mới. Chọn Xe máy để tránh dùng tuyến Ô tô.") }
                Section {
                    Toggle("Nhắc hai chỗ rẽ sát nhau",isOn:$navigator.chainedTurnsEnabled)
                    Toggle("Tổng km/phút trên đồng hồ",isOn:$navigator.watchTripInfoEnabled)
                } header: { Label("Nội dung Navigation",systemImage:"text.alignleft") }
                footer: { Text("Nhắc thao tác tiếp theo khi hai chỗ rẽ cách 10–100 m và bạn đang tới gần chỗ rẽ đầu. Ô phụ luân phiên tổng km và thời gian còn lại khoảng mỗi 5 giây khi có cập nhật GPS. Giờ đến và thời gian là ước tính theo tuyến.") }
                Section {
                    Text(navigator.locationStatus).font(.footnote)
                    Text(link.navigationDeliveryInfo).font(.footnote)
                } header: { Label("Tín hiệu cập nhật",systemImage: "antenna.radiowaves.left.and.right") }
                footer: { Text("Chỉ dẫn gửi khoảng mỗi giây khi có vị trí mới. Thời gian xác nhận đo kết nối với đồng hồ, không đo thời điểm màn hình đồng hồ vẽ xong.") }
                Section {
                    Label("Lịch sử lưu trên iPhone",systemImage: "iphone.and.arrow.forward")
                    Text("Lưu điểm đến, quãng đường, thời gian và tốc độ trung bình; không lưu đường GPS chi tiết. Bạn có thể xóa từng chuyến trong tab Lịch sử.").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("Tìm địa điểm và bản đồ: Apple. Tuyến xe máy: Valhalla/OpenStreetMap; vị trí đầu/cuối được gửi tới máy chủ FOSSGIS khi tính hoặc tự đổi tuyến.").font(.footnote)
                    Link("© OpenStreetMap contributors",destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                }
            }
            .navigationTitle("Tùy chọn").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Xong") { dismiss() } } }
        }
    }
}
