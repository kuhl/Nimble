//
//  WeakRef.swift
//  NimbleCore
//
//  Created by Grigory Markin on 12.11.19.
//  Copyright © 2019 SCADE. All rights reserved.
//

import Foundation

public struct WeakRef<T: AnyObject> {
  public weak var value: T? = nil
}
