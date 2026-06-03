//
//  LayerFontProvider.swift
//  Lottie
//
//  Created by Brandon Withrow on 8/5/20.
//  Copyright © 2020 YurtvilleProds. All rights reserved.
//

import Foundation

/// Connects a LottieFontProvider to a group of text layers
final class LayerFontProvider {

  init(fontProvider: AnimationFontProvider) {
    self.fontProvider = fontProvider
    textLayers = []
    reloadTexts()
  }

  private(set) var textLayers: [TextCompositionLayer]

  var fontProvider: AnimationFontProvider {
    didSet {
      reloadTexts()
    }
  }

  func addTextLayers(_ layers: [TextCompositionLayer]) {
    textLayers += layers
  }

  func reloadTexts() {
    textLayers.forEach {
      $0.fontProvider = fontProvider
    }
  }
}
