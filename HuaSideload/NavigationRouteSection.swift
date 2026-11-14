import MapKit
import SwiftUI

struct NavigationRouteSection: View {
    @ObservedObject var navigator: RouteNavigator
    @ObservedObject var link: WatchLink

    var body: some View {
        Section {
            Text(navigator.status).font(.callout)
            if !navigator.isNavigating && !link.mapsReader.isReading {
                Picker("Cách di chuyển", selection: $navigator.mode) {
                    ForEach(RouteNavigator.Mode.allCases) { Text($0.title).tag($0) }
                }
                Text(navigator.mode == .motorcycle ? "Tuyến xe máy: Valhalla/OpenStreetMap. Vị trí đầu/cuối được gửi tới máy chủ demo FOSSGIS khi bạn bấm Tính tuyến; bản đồ và tìm địa điểm do Apple cung cấp." : "Chọn đúng phương tiện. Tuyến Ô tô không dùng cho xe máy.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Lấy vị trí hiện tại") { navigator.requestLocation() }
                    .disabled(navigator.isCalculating)
                Text(navigator.locationStatus).font(.caption).foregroundStyle(.secondary)
                TextField("Tên hoặc địa chỉ điểm đến", text: $navigator.query)
                    .submitLabel(.search)
                    .onSubmit { navigator.searchDestination() }
                Button(navigator.isSearching ? "Đang tìm…" : "Tìm điểm đến") { navigator.searchDestination() }
                    .disabled(navigator.isSearching || navigator.isCalculating || navigator.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ForEach(navigator.results) { result in
                    Button { navigator.select(result) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.name)
                            Text(result.address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let destination = navigator.destination {
                LabeledContent("Điểm đến", value: destination.name)
                Text(link.navigationStatus).font(.caption).foregroundStyle(.secondary)
                if !navigator.isNavigating {
                    Text(destination.address).font(.caption).foregroundStyle(.secondary)
                    Button(navigator.isCalculating ? "Đang tính…" : "Tính tuyến đường") { navigator.calculateRoute() }
                        .disabled(navigator.isCalculating || navigator.isSearching)
                }
                if let polyline = navigator.displayPolyline {
                    Map {
                        MapPolyline(polyline).stroke(.blue, lineWidth: 5)
                        Marker(destination.name, coordinate: destination.item.placemark.coordinate)
                        UserAnnotation()
                    }
                    .mapControls { MapCompass() }
                    .frame(height: 220)
                    .id(navigator.routeRevision)
                    Text(navigator.preview).font(.callout)
                }
                if navigator.isNavigating {
                    Text(navigator.instruction).font(.headline)
                    Text(navigator.distanceToTurn)
                    Button("Dừng điều hướng", role: .destructive) { navigator.stop() }
                } else if navigator.hasRoute {
                    ForEach(Array(navigator.instructionPreview.prefix(5).enumerated()), id: \.offset) { _, text in
                        Text(text).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Bắt đầu gửi tới đồng hồ") { link.startRouteNavigation() }
                        .fontWeight(.semibold)
                        .disabled(link.commandsLocked || !link.isPaired)
                }
            }
        } header: {
            Text("Điều hướng chạy nền — bản đồ Apple")
        } footer: {
            VStack(alignment: .leading, spacing: 5) {
            Link("Dữ liệu tuyến xe máy © OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            Text("Bắt đầu khi app đang mở, cho phép Vị trí chính xác rồi mới khóa iPhone. Giữ Navigation mở trên đồng hồ và không vuốt tắt HuaSideload. Khi lệch tuyến, dừng và tính lại tuyến. Ưu tiên nội dung chỉ dẫn nếu biểu tượng chưa thể hiện đúng hướng.")
            }
        }
    }
}
