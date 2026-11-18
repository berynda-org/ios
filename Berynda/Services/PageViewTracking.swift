import BeryndaCore
import SwiftUI

extension View {
    /// Counts this screen in the site's page-view analytics each time it
    /// appears, and again when `path` changes (the catalog becoming a
    /// search). `path` is a `PageViewPath`: web-equivalent, with no query and
    /// nothing personal.
    func reportsPageView(_ path: String) -> some View {
        modifier(PageViewReportingModifier(path: path))
    }
}

private struct PageViewReportingModifier: ViewModifier {
    @EnvironmentObject private var environment: AppEnvironment
    let path: String

    func body(content: Content) -> some View {
        content.task(id: path) { environment.reportPageView(path) }
    }
}
