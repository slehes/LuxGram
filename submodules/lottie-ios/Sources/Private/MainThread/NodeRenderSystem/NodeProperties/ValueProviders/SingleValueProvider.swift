//
//  SingleValueProvider.swift
//  lottie-swift
//
//  Created by Brandon Withrow on 1/30/19.
//

import Foundation
import QuartzCore

/// Returns a value for every frame.
final class SingleValueProvider<ValueType: AnyInterpolatable>: ValueProvider {

  init(_ value: ValueType) {
    self.value = value
  }

  var value: ValueType {
    didSet {
      hasUpdate = true
    }
  }

  var storage: ValueProviderStorage<ValueType> {
    .singleValue(value)
  }

  var valueType: Any.Type {
    ValueType.self
  }

  func hasUpdate(frame _: CGFloat) -> Bool {
    hasUpdate
  }

  private var hasUpdate = true
}
