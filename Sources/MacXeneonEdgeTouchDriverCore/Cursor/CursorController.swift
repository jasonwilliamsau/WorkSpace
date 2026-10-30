import CoreGraphics
import Foundation

/// Manages cursor borrow, warp, and return operations.
public protocol CursorController: AnyObject {
    /// Saves the current cursor position, hides the cursor, and warps to `point`.
    ///
    /// - Returns: `true` if the cursor was borrowed and warped successfully.
    func borrow(warpingTo point: CGPoint) -> Bool

    /// Warps the borrowed cursor to a new gesture point.
    func updatePosition(_ point: CGPoint)

    /// Ends the cursor borrow and shows it. The implementation may restore the
    /// saved pre-touch position or leave the cursor at the last touch point.
    func returnToOrigin()

    /// Shows the cursor for recovery paths.
    func forceShow()
}
