import MapKit
import SwiftUI

struct FavoritePlacesView: View {
    @ObservedObject var navigator: RouteNavigator
    @ObservedObject var favorites: FavoritePlacesStore
    let captureOnOpen: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var editing: FavoritePlace?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { navigator.captureFavoriteGPS() } label: {
                        HStack {
                            Label("Lưu GPS hiện tại",systemImage:"location.fill")
                            Spacer()
                            if navigator.isCapturingFavorite { ProgressView() }
                        }
                    }.disabled(navigator.isCapturingFavorite)
                    if navigator.isCapturingFavorite {
                        Text("Đang chờ GPS chính xác…").font(.caption).foregroundStyle(.secondary)
                        Button("Hủy lấy vị trí",role:.cancel) { navigator.cancelFavoriteGPS() }
                    }
                    if let destination = navigator.destination {
                        Button {
                            let coordinate = destination.item.placemark.coordinate
                            editing = FavoritePlace(name:destination.name,latitude:coordinate.latitude,longitude:coordinate.longitude)
                        } label: { Label("Lưu điểm đến đang chọn",systemImage:"mappin.and.ellipse") }
                    }
                    if let error = navigator.favoriteCaptureError { Text(error).font(.caption).foregroundStyle(.red) }
                } footer: { Text("Đặt tên để lần sau chọn nhanh. Lưu GPS cần vị trí mới và sai số không quá 35 m.") }
                Section {
                    if favorites.places.isEmpty {
                        ContentUnavailableView("Chưa có địa điểm",systemImage:"star",description:Text("Lưu nhà, nơi làm việc hoặc vị trí bạn đang đứng."))
                    }
                    ForEach(favorites.places) { place in
                        Button {
                            guard !navigator.isNavigating else { return }
                            let item = MKMapItem(placemark:MKPlacemark(coordinate:.init(latitude:place.latitude,longitude:place.longitude)))
                            item.name = place.name
                            navigator.selectAndCalculate(.init(item:item)); dismiss()
                        } label: {
                            HStack(spacing:12) {
                                Image(systemName:"star.fill").foregroundStyle(.orange)
                                    .padding(10).background(Color.orange.opacity(0.1),in:RoundedRectangle(cornerRadius:12))
                                VStack(alignment:.leading,spacing:4) {
                                    Text(place.name).font(.headline).foregroundStyle(.primary)
                                    Text(String(format:"%.6f, %.6f",place.latitude,place.longitude)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName:"arrow.up.right").font(.caption.bold()).foregroundStyle(.blue)
                            }.padding(.vertical,5)
                        }
                        .disabled(navigator.isNavigating || navigator.isCalculating)
                        .swipeActions(edge:.trailing) {
                            Button("Xóa",role:.destructive) { favorites.delete(place.id) }
                            Button("Sửa tên") { editing = place }.tint(.blue)
                        }
                        .contextMenu {
                            Button("Sửa tên",systemImage:"pencil") { editing = place }
                            Button("Xóa",systemImage:"trash",role:.destructive) { favorites.delete(place.id) }
                        }
                    }
                } header: { Text("Đã lưu · \(favorites.places.count)") }
                footer: { Text(navigator.isNavigating ? "Kết thúc chuyến hiện tại trước khi dẫn đường tới địa điểm khác. Bạn vẫn có thể lưu GPS." : "Chạm địa điểm để tính tuyến. Vuốt sang trái để sửa tên hoặc xóa.") }
                if let message = favorites.storageMessage { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
                Section { Text("Tên và tọa độ được lưu riêng trên iPhone. Khi chọn để tính tuyến xe máy, tọa độ được gửi tới nhà cung cấp tuyến như các điểm đến khác.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Yêu thích").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Xong") { dismiss() } } }
            .sheet(item:$editing) { place in FavoritePlaceEditor(place:place,favorites:favorites) }
            .onChange(of:navigator.capturedFavorite) { _, place in if let place { editing = place } }
            .onDisappear { navigator.cancelFavoriteGPS() }
            .task {
                if captureOnOpen { navigator.captureFavoriteGPS() }
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.environment["HUASIDELOAD_UI_PREVIEW"] == "favorite-editor" {
                    editing = FavoritePlace(name:"Vị trí hiện tại",latitude:10.77645,longitude:106.70092)
                }
                #endif
            }
        }
    }
}

private struct FavoritePlaceEditor: View {
    let place: FavoritePlace
    @ObservedObject var favorites: FavoritePlacesStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(place: FavoritePlace,favorites: FavoritePlacesStore) {
        self.place = place; self.favorites = favorites
        _name = State(initialValue:place.name)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Tên địa điểm") {
                    TextField("Ví dụ: Nhà, Công ty…",text:$name).submitLabel(.done).onSubmit { save() }
                    Text("Tối đa 60 ký tự.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Vị trí đã chọn") {
                    Map(initialPosition:.region(MKCoordinateRegion(
                        center:.init(latitude:place.latitude,longitude:place.longitude),
                        span:.init(latitudeDelta:0.003,longitudeDelta:0.003)))) {
                        Marker(name.isEmpty ? "Vị trí" : name,coordinate:.init(latitude:place.latitude,longitude:place.longitude))
                    }.frame(height:180).allowsHitTesting(false)
                    Text(String(format:"%.6f, %.6f",place.latitude,place.longitude)).font(.callout.monospacedDigit())
                    Text("Lưu tên không làm thay đổi tọa độ.").font(.caption).foregroundStyle(.secondary)
                }
                if let message = favorites.storageMessage { Section { Text(message).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("Lưu địa điểm").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement:.topBarTrailing) { Button("Lưu",action:save).bold().disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
            }
        }
    }
    private func save() {
        var result = place; result.name = name
        if favorites.save(result) { dismiss() }
    }
}
