//
//  NimbleSidebarArea.swift
//  Nimble
//
//  Copyright © 2021 SCADE Inc. All rights reserved.
//
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Cocoa
import NimbleCore


public class NimbleSidebarArea: NSViewController {
  @IBOutlet var sidebar: WorkbenchSidebar? = nil
  var stateChanged: ((Int) -> Void)?
}


extension NimbleSidebarArea: WorkbenchArea {
  public var parts: [WorkbenchPart] {
    self.children.compactMap{$0 as? WorkbenchPart}
  }

  public func add(part: WorkbenchPart) {
    if let part = part as? NSViewController {
      self.addChild(part)
    }
    
    sidebar?.appendView(part.view, title: part.title ?? "", icon: part.icon)
  }

  public func show(part: WorkbenchPart) {
    guard let child = part as? NSViewController,
          let pos = self.children.firstIndex(of: child) else { return }

    stateChanged?(pos)
    sidebar?.selectView(at: pos)
  }
}


