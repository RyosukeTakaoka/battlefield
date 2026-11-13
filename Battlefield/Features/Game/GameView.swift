import RealityKit
import SwiftUI

/// RealityKit の ARView を SwiftUI に置くための包み.
struct GameView: UIViewRepresentable {
    let controller: FlightController

    func makeUIView(context: Context) -> ARView {
        controller.makeView()
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
