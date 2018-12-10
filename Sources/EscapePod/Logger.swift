//
//  Loggr.swift
//  Files
//
//  Created by Shane Whitehead on 3/9/18.
//

import Foundation

public func log(_ values: String...) {
	var value: [String] = []
	value.append(contentsOf: values)
	value.insert("*** ".green, at: 0)
	print(value.joined(separator: " "))
}

public func log(error: String...) {
	var values: [String] = []
	values.append(contentsOf: error)
	values.insert("*** ".red, at: 0)
	print(values.joined(separator: " "))
}

public func log(warning: String...) {
	var values: [String] = []
	values.append(contentsOf: warning)
	values.insert("*** ".yellow, at: 0)
	print(values.joined(separator: " "))
}

public func log(debug: String...) {
	var values: [String] = []
	values.append(contentsOf: debug)
	values.insert("*** ".lightBlack, at: 0)
	print(values.joined(separator: " "))
}
