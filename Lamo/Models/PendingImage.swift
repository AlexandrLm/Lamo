import UIKit

/// Identifiable wrapper for UIImage used in pending-attachments UI.
struct PendingImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
