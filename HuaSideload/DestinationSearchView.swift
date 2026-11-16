import MapKit
import SwiftUI

struct DestinationSearchView: View {
    @ObservedObject var navigator: RouteNavigator
    var addingStop = false
    @StateObject private var search = DestinationSearchModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var appeared = false
    @State private var visualPreview = false

    var body: some View {
        Group {
            if let pin = search.selected {
                MapPinDestinationView(pin:pin,navigator:navigator,favorites:navigator.favorites,
                    onlyStopover:addingStop,onBack:{ search.backToResults() })
            } else { searchPage }
        }
        .onDisappear { search.cancel() }
        .onAppear {
            guard !appeared else { return }; appeared = true
            #if DEBUG && targetEnvironment(simulator)
            if let preview = ProcessInfo.processInfo.environment["HUASIDELOAD_UI_PREVIEW"],preview.hasPrefix("search-") {
                visualPreview = true; query = "Bưu điện"; search.prepareVisualPreview(preview); return
            }
            #endif
            focused = true
            if !navigator.hasLocation { navigator.requestLocation() }
        }
    }

    private var searchPage: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { favorites }
                else {
                    Section {
                        if search.phase == .suggestions || search.phase == .suggesting {
                            ForEach(search.suggestions) { item in
                                Button {
                                    focused = false; search.resolve(item,region:navigator.destinationSearchRegion)
                                } label: { placeRow(item.title,address:item.subtitle,icon:"magnifyingglass",color:.blue) }
                                    .accessibilityIdentifier("place-suggestion")
                            }
                        } else {
                            ForEach(search.results) { place in
                                Button { focused = false; search.choose(place) } label: {
                                    placeRow(place.name,address:place.address,icon:"mappin",color:.orange)
                                }.accessibilityIdentifier("place-result")
                            }
                        }
                        if search.busy {
                            HStack(spacing:12) {
                                ProgressView()
                                Text(search.phase == .suggesting ? "Đang tìm gợi ý…" : search.phase == .resolving ? "Đang lấy địa điểm…" : "Đang tìm địa điểm…")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical,12)
                        }
                        if !search.message.isEmpty {
                            VStack(alignment:.leading,spacing:10) {
                                Label(search.message,systemImage:search.phase == .failed ? "wifi.exclamationmark" : "magnifyingglass")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if search.phase == .failed {
                                    Button("Thử lại") { submit() }.font(.subheadline.bold())
                                }
                            }.padding(.vertical,12)
                        }
                    } header: {
                        HStack {
                            Text(search.phase == .suggestions || search.phase == .suggesting ? "Gợi ý địa điểm" : "Kết quả tìm kiếm")
                            Spacer()
                            if search.phase == .results { Text("\(search.results.count) địa điểm") }
                        }.textCase(nil)
                    } footer: {
                        Text("Chọn một địa điểm để kiểm tra ghim trên bản đồ trước khi \(addingStop ? "thêm điểm dừng" : "chọn tuyến").")
                    }
                }
            }
            .listStyle(.insetGrouped).scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge:.top,spacing:0) { searchHeader }
            .navigationTitle(addingStop ? "Thêm điểm dừng" : "Tìm điểm đến")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Xong") { dismiss() } } }
        }
    }

    private var searchHeader: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(.blue)
                TextField("Tên địa điểm hoặc địa chỉ",text:$query)
                    .focused($focused).submitLabel(.search).autocorrectionDisabled()
                    .onSubmit { submit() }
                    .onChange(of:query) { _,value in
                        if !visualPreview { search.edit(value,region:navigator.destinationSearchRegion) }
                    }
                    .accessibilityIdentifier("destination-search-input")
                if !query.isEmpty {
                    Button { query = ""; focused = true } label: {
                        Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary)
                            .frame(width:28,height:32)
                    }.buttonStyle(.plain).accessibilityLabel("Xóa nội dung tìm kiếm")
                }
            }
            .padding(.horizontal,14).padding(.vertical,10)
            .background(Color(.tertiarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:16))
            Text("Gõ để xem gợi ý · Enter để tìm đầy đủ")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal,20).padding(.vertical,12).background(.regularMaterial)
    }

    private var favorites: some View {
        Section {
            if navigator.favorites.places.isEmpty {
                ContentUnavailableView("Tìm nơi bạn muốn đến",systemImage:"map",
                    description:Text("Nhập tên quán, địa danh hoặc địa chỉ. Gợi ý sẽ xuất hiện khi bạn gõ."))
            } else {
                ForEach(navigator.favorites.places) { place in
                    Button {
                        focused = false
                        let item = MKMapItem(placemark:MKPlacemark(coordinate:.init(latitude:place.latitude,longitude:place.longitude)))
                        item.name = place.name; search.choose(.init(item:item))
                    } label: { placeRow(place.name,address:"Địa điểm đã lưu",icon:"star.fill",color:.orange) }
                }
            }
        } header: { if !navigator.favorites.places.isEmpty { Text("Yêu thích").textCase(nil) } }
    }

    private func submit() {
        guard !visualPreview else { return }
        focused = false; search.submit(query,region:navigator.destinationSearchRegion)
    }
    private func placeRow(_ title: String,address: String,icon: String,color: Color) -> some View {
        HStack(spacing:12) {
            Image(systemName:icon).font(.body.weight(.semibold)).foregroundStyle(color)
                .frame(width:38,height:38).background(color.opacity(0.1),in:RoundedRectangle(cornerRadius:12))
            VStack(alignment:.leading,spacing:5) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                if !address.isEmpty { Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength:2)
            Image(systemName:"chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary)
        }.padding(.vertical,6).contentShape(Rectangle())
    }
}
