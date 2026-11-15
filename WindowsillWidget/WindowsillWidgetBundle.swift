//
//  WindowsillWidgetBundle.swift
//  WindowsillWidget
//
//  Created by Roha Fatima on 11/13/26.
//

import WidgetKit
import SwiftUI

@main
struct WindowsillWidgetBundle: WidgetBundle {
    init() {
        Fonts.register()
    }

    var body: some Widget {
        WindowsillWidget()
    }
}
