///
/// ColoredStream.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation

public protocol ColoredStream: TextOutputStream {
    mutating func write(_ string: String, with: [ANSIColor])
}

extension ColoredStream {
    public mutating func write(_ string: String) {
        write(string, with: [])
    }
}

public class ColoredANSIStream<StreamType: TextOutputStream>: ColoredStream {
    private var currentColors = [ANSIColor]()
    private var stream: StreamType
    private let isColored: Bool

    public init(_ stream: inout StreamType, colored: Bool = true) {
        self.stream = stream
        self.isColored = colored
    }

    public required init(_ stream: inout StreamType) {
        self.stream = stream
        self.isColored = true
    }

    public func addColor(_ color: ANSIColor) {
        guard isColored else { return }
        stream.write(color.rawValue)
        currentColors.append(color)
    }

    public func reset() {
        if currentColors.isEmpty { return }
        stream.write(ANSIColor.reset.rawValue)
        currentColors = []
    }

    public func setColors(_ colors: [ANSIColor]) {
        guard isColored else { return }
        reset()
        for color in colors {
            stream.write(color.rawValue)
        }
        currentColors = colors
    }

    public func write(_ string: String) {
        stream.write(string)
    }

    public func write(_ string: String, with colors: [ANSIColor]) {
        self.setColors(colors)
        write(string)
        self.reset()
    }
}
