//
//  NSScreen+IDs.swift
//  FastSwitch
//
//  Created by Gaston on 31/08/2025.
//

import AppKit
import CoreGraphics

extension NSScreen {
    var cgID: CGDirectDisplayID? {
        guard let num = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return CGDirectDisplayID(num.uint32Value)
    }
    var displayUUIDString: String? {
        guard let id = cgID, let unmanaged = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let u = unmanaged.takeRetainedValue()
        return CFUUIDCreateString(nil, u) as String
    }
}
