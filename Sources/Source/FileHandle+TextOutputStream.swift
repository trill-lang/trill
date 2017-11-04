///
/// FileHandle+TextOutputStream.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation

extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        write(string.data(using: .utf8)!)
    }
}
