import MapKit
import SwiftUI

struct RouteStopoversView: View {
    @ObservedObject var navigator: RouteNavigator
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Vị trí GPS của bạn",systemImage:"location.fill").foregroundStyle(.blue)
                } header: { Text("Khởi hành") }
                Section {
                    if navigator.stopovers.isEmpty {
                        Text("Thêm nơi ghé trước khi tới điểm cuối.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(navigator.stopovers.enumerated()),id: \.element.id) { index,stop in
                        HStack(spacing:12) {
                            Text("\(index+1)").font(.headline).foregroundStyle(.purple)
                                .frame(width:30,height:30).background(.purple.opacity(0.1),in:Circle())
                            VStack(alignment:.leading,spacing:4) {
                                Text(stop.name).font(.headline)
                                Text(stop.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength:0)
                            VStack(spacing:12) {
                                Button { navigator.moveStopover(stop.id,direction:-1) } label: { Image(systemName:"chevron.up") }
                                    .disabled(index == 0)
                                Button { navigator.moveStopover(stop.id,direction:1) } label: { Image(systemName:"chevron.down") }
                                    .disabled(index == navigator.stopovers.count-1)
                            }.font(.caption.bold()).buttonStyle(.borderless)
                        }.padding(.vertical,4)
                            .swipeActions { Button("Xóa",role:.destructive) { navigator.removeStopover(stop.id) } }
                    }
                    if navigator.stopovers.count < 3 {
                        Button { adding = true } label: { Label("Thêm điểm dừng",systemImage:"plus.circle.fill") }
                    }
                } header: { Text("Điểm dừng · \(navigator.stopovers.count)/3") }
                footer: { Text("Đi theo thứ tự từ trên xuống. Vuốt một điểm sang trái để xóa; dùng mũi tên để đổi thứ tự. Đến gần điểm dừng với GPS chính xác, app tự chuyển sang chặng tiếp theo.") }
                Section {
                    Label(navigator.destination?.name ?? "Chưa chọn điểm đến",systemImage:"flag.checkered")
                } header: { Text("Điểm cuối") }
                Section {
                    Text("Tuyến qua điểm dừng được tính trọn hành trình. Bản này trả về một tuyến khi có điểm dừng; tổng km/phút là cho toàn bộ các chặng.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(navigator.isNavigating || navigator.isCalculating)
            .navigationTitle("Điểm dừng").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) {
                Button("Xong") {
                    dismiss()
                    if !navigator.hasRoute, !navigator.isCalculating { navigator.calculateWhenReady() }
                }
            } }
            .sheet(isPresented:$adding) { DestinationSearchView(navigator:navigator,addingStop:true) }
        }
    }
}
