#if os(iOS)
import SwiftUI

public struct WASpacesiOSAppRoot: App {
  @StateObject private var viewModel = IOSAppViewModel.makeDemo()

  public init() {}

  public var body: some Scene {
    WindowGroup {
      IOSRootView(viewModel: viewModel)
    }
  }
}
#else
public enum WASpacesiOSAppRootPlaceholder {}
#endif
