import Foundation
import UIKit

/// Identifiable wrapper for UIImage used in pending-attachments UI.
struct PendingImage: Identifiable, Equatable, Hashable {
    let id = UUID()
    let image: UIImage

    static func == (lhs: PendingImage, rhs: PendingImage) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
