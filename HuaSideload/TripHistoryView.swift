import SwiftUI

enum RideFormat {
    static func distance(_ meters: Double) -> String { meters < 1000 ? "\(Int(max(0,meters))) m" : String(format: "%.1f km",meters/1000) }
    static func date(_ value: Date) -> String {
        value.formatted(Date.FormatStyle(date: .abbreviated,time: .shortened).locale(Locale(identifier: "vi_VN")))
    }
    static func speed(_ value: Double) -> String { String(format: "%.1f",value) }
    static func duration(_ seconds: Double) -> String {
        let total = max(0,Int(seconds))
        if total < 60 { return "\(total) giây" }
        if total < 3600 { return "\(total/60) phút" }
        return "\(total/3600)g \((total%3600)/60)p"
    }
}

struct TripHistoryView: View {
    @ObservedObject var history: TripHistoryStore
    var onRepeatTrip: ((String) -> Void)? = nil
    @State private var confirmingClear = false
    var body: some View {
        NavigationStack {
            List {
                if let message = history.storageMessage { Section { Text(message).foregroundStyle(.orange) } }
                if history.records.isEmpty {
                    ContentUnavailableView("Chưa có hành trình",systemImage: "clock.arrow.circlepath",
                        description: Text("Chuyến đi sẽ xuất hiện ở đây sau khi bạn kết thúc điều hướng."))
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        VStack(alignment: .leading,spacing: 12) {
                            Label("NHỮNG CHUYẾN ĐÃ ĐI",systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.caption.bold()).tracking(1)
                            Text(RideFormat.distance(history.records.reduce(0) { $0+$1.distance }))
                                .font(.system(size: 34,weight: .bold,design: .rounded))
                            Text("\(history.records.count) hành trình được lưu trên iPhone").font(.subheadline)
                        }.foregroundStyle(.white).padding(.vertical,10)
                    }.listRowBackground(LinearGradient(colors: [.blue,.indigo],startPoint: .topLeading,endPoint: .bottomTrailing))
                    Section("Gần đây") {
                        ForEach(history.records) { trip in
                            NavigationLink {
                                TripDetailView(trip: trip, onRepeatTrip: onRepeatTrip)
                            } label: {
                                HStack(alignment: .top,spacing: 12) {
                                    Image(systemName: trip.mode == "Xe máy" ? "motorcycle" : (trip.mode == "Đi bộ" ? "figure.walk" : "car.fill"))
                                        .font(.title3).foregroundStyle(.blue).frame(width: 40,height: 40)
                                        .background(.blue.opacity(0.08),in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading,spacing: 5) {
                                        Text(trip.destination).font(.headline).lineLimit(1)
                                        Text(RideFormat.date(trip.startedAt)).font(.caption).foregroundStyle(.secondary)
                                        Text("\(RideFormat.distance(trip.distance)) · \(RideFormat.duration(trip.duration))")
                                            .font(.subheadline)
                                        Text(trip.outcomeLabel).font(.caption2).foregroundStyle(trip.outcome == .completed ? Color.green : Color.secondary)
                                    }
                                }.padding(.vertical,5)
                            }
                            .swipeActions {
                                Button("Xóa",role: .destructive) { history.delete(trip.id) }
                                if let onRepeatTrip {
                                    Button("Đi lại") { onRepeatTrip(trip.destination) }.tint(.blue)
                                }
                            }
                        }
                    }
                    Section { Text("Quãng đường và tốc độ là ước lượng từ GPS. Không lưu tọa độ hay đường đi chi tiết. Vuốt sang trái hoặc mở chi tiết để tìm đường đi lại.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Lịch sử")
            .toolbar {
                if !history.records.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { confirmingClear = true } label: { Image(systemName: "trash") }.accessibilityLabel("Xóa lịch sử")
                    }
                }
            }
            .confirmationDialog("Xóa toàn bộ lịch sử đã lưu?",isPresented: $confirmingClear,titleVisibility: .visible) {
                Button("Xóa lịch sử",role: .destructive) { history.clear() }
                Button("Hủy",role: .cancel) {}
            }
        }
    }
}

private struct TripDetailView: View {
    let trip: TripRecord
    var onRepeatTrip: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section {
                Text(trip.destination).font(.title2.bold())
                Label(trip.outcomeLabel,systemImage: trip.outcome == .completed ? "checkmark.circle.fill" : "pause.circle")
                    .foregroundStyle(.secondary)
                if let onRepeatTrip {
                    Button {
                        dismiss()
                        onRepeatTrip(trip.destination)
                    } label: {
                        Label("Tìm đường đi lại nơi này", systemImage: "location.north.fill")
                            .fontWeight(.semibold)
                    }
                }
            }
            Section("Thống kê hành trình") {
                LabeledContent("Quãng đường GPS",value: RideFormat.distance(trip.distance))
                LabeledContent("Thời gian",value: RideFormat.duration(trip.duration))
                LabeledContent("Tốc độ trung bình",value: RideFormat.speed(trip.averageSpeed)+" km/h")
                LabeledContent("Phương tiện",value: trip.mode)
            }
            Section("Thời gian") {
                LabeledContent("Bắt đầu",value: RideFormat.date(trip.startedAt))
                LabeledContent("Kết thúc",value: RideFormat.date(trip.endedAt))
            }
        }.navigationTitle("Hành trình").navigationBarTitleDisplayMode(.inline)
    }
}
