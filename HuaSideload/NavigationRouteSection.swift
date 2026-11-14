import MapKit
import SwiftUI

struct NavigationRouteSection: View {
    @ObservedObject var navigator: RouteNavigator
    @ObservedObject var link: WatchLink

    var body: some View {
        Section {
            Text(navigator.status).font(.callout)
            if !navigator.isNavigating {
                Picker("Cách di chuyển", selection: $navigator.mode) {
                    ForEach(RouteNavigator.Mode.allCases) { Text($0.title).tag($0) }
                }
                Text("Ô tô có thể đi vào đường cấm xe máy. Bản thử chưa có tuyến riêng cho xe máy.")
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
                if !navigator.isNavigating {
                    Text(destination.address).font(.caption).foregroundStyle(.secondary)
                    Button(navigator.isCalculating ? "Đang tính…" : "Tính tuyến đường") { navigator.calculateRoute() }
                        .disabled(navigator.isCalculating || navigator.isSearching)
                }
                if let route = navigator.displayRoute {
                    Map {
                        MapPolyline(route.polyline).stroke(.blue, lineWidth: 5)
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
                    Button("Bắt đầu gửi tới đồng hồ") { navigator.start() }
                        .fontWeight(.semibold)
                        .disabled(link.commandsLocked || !link.isPaired)
                }
            }
        } header: {
            Text("Apple Maps — điều hướng thử nghiệm")
        } footer: {
            Text("Bắt đầu khi app đang mở, cho phép Vị trí chính xác rồi mới khóa iPhone. Giữ Navigation mở trên đồng hồ và không vuốt tắt HuaSideload. Khi lệch tuyến, dừng và tính lại tuyến. Ưu tiên nội dung chỉ dẫn nếu biểu tượng chưa thể hiện đúng hướng.")
        }
    }
}
