#if os(iOS)
import SwiftUI

public struct WASpacesiOSAppRoot: App {
  @StateObject private var viewModel: IOSAppViewModel

  public init() {
    _viewModel = StateObject(wrappedValue: IOSAppViewModel.makeLive())
  }

  public var body: some Scene {
    WindowGroup {
      IOSRootView(viewModel: viewModel)
    }
  }
}
#else
public enum WASpacesiOSAppRootPlaceholder {}
#endif
