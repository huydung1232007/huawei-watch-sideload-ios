import MapKit
import SwiftUI

struct SelectedMapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    var name: String? = nil
    var title = "Ghim trên bản đồ"
}

struct MapPinDestinationView: View {
    let pin: SelectedMapPin
    @ObservedObject var navigator: RouteNavigator
    @ObservedObject var favorites: FavoritePlacesStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Điểm đã ghim"
    private let onlyStopover: Bool
    private let onBack: (() -> Void)?
    private var trimmedName: String { name.trimmingCharacters(in:.whitespacesAndNewlines) }
    private var validName: Bool { !trimmedName.isEmpty && trimmedName.count <= 60 }

    init(pin: SelectedMapPin,navigator: RouteNavigator,favorites: FavoritePlacesStore,onlyStopover: Bool = false,onBack: (() -> Void)? = nil) {
        self.pin = pin; self.navigator = navigator; self.favorites = favorites
        self.onlyStopover = onlyStopover; self.onBack = onBack
        _name = State(initialValue:pin.name ?? "Điểm đã ghim")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vị trí bạn chọn") {
                    Map(initialPosition:.region(MKCoordinateRegion(center:pin.coordinate,
                        span:.init(latitudeDelta:0.004,longitudeDelta:0.004))),interactionModes:[]) {
                        Marker(trimmedName.isEmpty ? "Điểm đã ghim" : trimmedName,coordinate:pin.coordinate).tint(.orange)
                    }.frame(height:200)
                    Text(String(format:"%.6f, %.6f",pin.coordinate.latitude,pin.coordinate.longitude))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Section("Tên địa điểm") {
                    TextField("Tên để nhận diện vị trí",text:$name)
                    if !validName { Text("Nhập tên từ 1 đến 60 ký tự.").font(.caption).foregroundStyle(.red) }
                }
                Section {
                  if !onlyStopover {
                    Button {
                        guard validName,!navigator.isNavigating,!navigator.isCalculating else { return }
                        let item = MKMapItem(placemark:MKPlacemark(coordinate:pin.coordinate)); item.name = trimmedName
                        navigator.selectAndCalculate(.init(item:item)); dismiss()
                    } label: { Label("Đi tới đây",systemImage:"location.north.fill") }
                    .disabled(!validName || navigator.isNavigating || navigator.isCalculating)
                    .accessibilityIdentifier("pin-route")
                  }
                    if navigator.destination != nil {
                        Button {
                            guard validName,navigator.canAddStopover else { return }
                            let item = MKMapItem(placemark:MKPlacemark(coordinate:pin.coordinate)); item.name = trimmedName
                            navigator.addStopover(.init(item:item)); navigator.calculateWhenReady(); dismiss()
                        } label: { Label("Thêm làm điểm dừng",systemImage:"plus.circle") }
                        .disabled(!validName || !navigator.canAddStopover)
                    }
                    Button {
                        guard validName else { return }
                        let place = FavoritePlace(name:trimmedName,latitude:pin.coordinate.latitude,longitude:pin.coordinate.longitude)
                        if favorites.save(place) { dismiss() }
                    } label: { Label("Lưu yêu thích",systemImage:"star.fill") }
                    .disabled(!validName).accessibilityIdentifier("pin-save")
                } footer: { Text("Kiểm tra ghim trước khi chọn. Đi tới đây sẽ tính tuyến từ vị trí GPS của bạn; lưu yêu thích chỉ lưu điểm này.") }
                if let message = favorites.storageMessage {
                    Section { Text(message).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(pin.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) { Button("Hủy") { dismiss() } }
                if let onBack { ToolbarItem(placement:.topBarLeading) { Button("Quay lại",action:onBack) } }
            }
        }
    }
}
