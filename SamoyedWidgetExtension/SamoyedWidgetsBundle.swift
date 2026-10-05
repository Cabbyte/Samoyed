import SwiftUI
import WidgetKit

@main
struct SamoyedWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SamoyedNowWidget()
        if #available(iOS 16.1, *) {
            SamoyedCurrentBlockLiveActivity()
        }
    }
}
