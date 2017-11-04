///
/// Array+Safe.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation

extension Array {
    public subscript(safe index: Int) -> Element? {
        guard index < count, index >= 0 else { return nil }
        return self[index]
    }
}
