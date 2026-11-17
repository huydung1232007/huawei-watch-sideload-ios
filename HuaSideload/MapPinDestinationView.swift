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
    @State private var coordinate: CLLocationCoordinate2D
    @State private var camera: MapCameraPosition
    private let onlyStopover: Bool
    private let onBack: (() -> Void)?
    private var trimmedName: String { name.trimmingCharacters(in:.whitespacesAndNewlines) }
    private var validName: Bool { !trimmedName.isEmpty && trimmedName.count <= 60 }

    init(pin: SelectedMapPin,navigator: RouteNavigator,favorites: FavoritePlacesStore,onlyStopover: Bool = false,onBack: (() -> Void)? = nil) {
        self.pin = pin; self.navigator = navigator; self.favorites = favorites
        self.onlyStopover = onlyStopover; self.onBack = onBack
        _name = State(initialValue:pin.name ?? "Điểm đã ghim")
        _coordinate = State(initialValue:pin.coordinate)
        _camera = State(initialValue:.region(MKCoordinateRegion(center:pin.coordinate,
            span:.init(latitudeDelta:0.004,longitudeDelta:0.004))))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MapReader { proxy in
                        Map(position: $camera) {
                            Marker(trimmedName.isEmpty ? "Điểm đã ghim" : trimmedName,coordinate:coordinate).tint(.orange)
                            UserAnnotation()
                        }
                        .frame(height:230)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    camera = .region(MKCoordinateRegion(center: coordinate,
                                        span: .init(latitudeDelta: 0.004, longitudeDelta: 0.004)))
                                }
                            } label: {
                                Label("Về ghim", systemImage: "scope")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.regularMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.6, maximumDistance: 12)
                                .simultaneously(with: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                                .onEnded { press in
                                    guard press.first == true, let touch = press.second,
                                          let moved = proxy.convert(touch.startLocation, from: .local),
                                          CLLocationCoordinate2DIsValid(moved) else { return }
                                    coordinate = moved
                                }
                        )
                    }
                    HStack {
                        Text(String(format:"%.6f, %.6f",coordinate.latitude,coordinate.longitude))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        if let badge = navigator.distanceBadge(to: coordinate) {
                            Text("Cách bạn ~\(badge)").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                        }
                    }
                } header: {
                    Text("Vị trí bạn chọn")
                } footer: {
                    Text("Có thể phóng to/kéo bản đồ để kiểm tra ngã tư và chiều đường; chạm giữ trên bản đồ nếu cần dời ghim sang đúng cổng.")
                }
                Section("Tên địa điểm") {
                    TextField("Tên để nhận diện vị trí",text:$name)
                    if !validName { Text("Nhập tên từ 1 đến 60 ký tự.").font(.caption).foregroundStyle(.red) }
                }
                Section {
                  if !onlyStopover {
                    Button {
                        guard validName,!navigator.isNavigating,!navigator.isCalculating else { return }
                        let item = MKMapItem(placemark:MKPlacemark(coordinate:coordinate)); item.name = trimmedName
                        navigator.selectAndCalculate(.init(item:item)); dismiss()
                    } label: { Label("Đi tới đây",systemImage:"location.north.fill") }
                    .disabled(!validName || navigator.isNavigating || navigator.isCalculating)
                    .accessibilityIdentifier("pin-route")
                  }
                    if navigator.destination != nil {
                        Button {
                            guard validName,navigator.canAddStopover else { return }
                            let item = MKMapItem(placemark:MKPlacemark(coordinate:coordinate)); item.name = trimmedName
                            navigator.addStopover(.init(item:item))
                            if !onlyStopover { navigator.calculateWhenReady() }
                            dismiss()
                        } label: { Label("Thêm làm điểm dừng",systemImage:"plus.circle") }
                        .disabled(!validName || !navigator.canAddStopover)
                    }
                    Button {
                        guard validName else { return }
                        let place = FavoritePlace(name:trimmedName,latitude:coordinate.latitude,longitude:coordinate.longitude)
                        if favorites.save(place) { dismiss() }
                    } label: { Label("Lưu yêu thích",systemImage:"star.fill") }
                    .disabled(!validName).accessibilityIdentifier("pin-save")
                } footer: {
                    Text(onlyStopover ? "Kiểm tra ghim rồi thêm vào danh sách điểm dừng. Bấm Xong ở danh sách để tính toàn bộ hành trình." : "Kiểm tra ghim trước khi chọn. Đi tới đây sẽ tính tuyến từ vị trí GPS của bạn; lưu yêu thích chỉ lưu điểm này.")
                }
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
