#if os(iOS)
import SwiftUI

public struct WASpacesiOSAppRoot: App {
  @StateObject private var model: IOSWebKitAppModel

  public init() {
    do {
      let instance = try IOSWebKitAppModel()
      _model = StateObject(wrappedValue: instance)
    } catch {
      fatalError("Falha ao iniciar runtime iOS WebKit: \(error)")
    }
  }

  public var body: some Scene {
    WindowGroup {
      IOSWebKitRootView(model: model)
    }
  }
}
#else
public enum WASpacesiOSAppRootPlaceholder {}
#endif
