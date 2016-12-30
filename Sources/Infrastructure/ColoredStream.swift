//
//  ColoredStream.swift
//  Trill
//
//  Created by Harlan Haskins on 12/30/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

import Foundation

class ColoredStream<StreamType: TextOutputStream>: TextOutputStream {
    var currentColors = [ANSIColor]()
    var stream: StreamType
    let colored: Bool
    
    init(_ stream: inout StreamType, colored: Bool = true) {
        self.stream = stream
        self.colored = colored
    }
    
    func addColor(_ color: ANSIColor) {
        guard colored else { return }
        stream.write(color.rawValue)
        currentColors.append(color)
    }
    
    func reset() {
        if currentColors.isEmpty { return }
        stream.write(ANSIColor.reset.rawValue)
        currentColors = []
    }
    
    func setColors(_ colors: [ANSIColor]) {
        guard colored else { return }
        reset()
        for color in colors {
            stream.write(color.rawValue)
        }
        currentColors = colors
    }
    
    func write(_ string: String) {
        stream.write(string)
    }
    
    func write(_ string: String, with colors: [ANSIColor]) {
        self.setColors(colors)
        write(string)
        self.reset()
    }
}
