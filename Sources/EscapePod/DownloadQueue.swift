//
//  File.swift
//  Basic
//
//  Created by Shane Whitehead on 10/12/18.
//

import Foundation
import SwiftSoup

class DownloadQueue: NSObject {
	static let shared = DownloadQueue()
	
	var semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
	
	var queue: OperationQueue = {
		let queue = OperationQueue()
		queue.qualityOfService = .userInitiated
		queue.maxConcurrentOperationCount = 4
		
		return queue
	}()
	
	func add(page: URL) {
		queue.addOperation(PageOperation(url: page))
	}
	
	func completed(operation: PageOperation) {
		DispatchQueue.global().async {
			Thread.sleep(forTimeInterval: 1.0)
			self.checkCompleted()
		}
	}
	
	@objc func checkCompleted() {
		log(debug: "Page count = \(queue.operationCount)")
		guard queue.operationCount == 0 else {
			return
		}
		semaphore.signal()
	}
}

class PageOperation: Operation {
	
	let url: URL
	
	init(url: URL) {
		self.url = url
	}
	
	enum Error: Swift.Error {
		case unknownResponse
		case badResponse(value: HTTPURLResponse)
		case noData
	}
	
	override func main() {
		guard !isCancelled else { return }
		log(debug: "Download page from \(url)")
		read(url: url, then: { (data) in
			defer {
				log(debug: "Completed processing \(self.url)")
				DownloadQueue.shared.completed(operation: self)
			}
			log(debug: "Parse page result from \(self.url)")
			guard let text = String(data: data, encoding: .utf8) else {
				log(error: "Could not parse result from \(self.url) to text")
				return
			}
			do {
				let doc: Document = try SwiftSoup.parse(text)
			} catch let error {
				log(error: error.localizedDescription)
			}
		}) { (error) in
			log(error: error.localizedDescription)
			DownloadQueue.shared.completed(operation: self)
		}
	}
	
	func read(url: URL, then: @escaping (Data) -> Void, fail: @escaping (Swift.Error) -> Void) {
		let sessionConfig = URLSessionConfiguration.default
		let session = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		
		let task = session.dataTask(with: request) { (data: Data?, response: URLResponse?, error: Swift.Error?) in
			log(debug: "Download request for \(url) completed")
			if let error = error {
				fail(error)
				return
			}
			guard let status = response as? HTTPURLResponse else {
				log(error: "Expecting HTTPURLResponse")
				fail(Error.unknownResponse)
				return
			}
			guard status.statusCode == 200 else {
				log(error: "\(url) return \(status.statusCode) - \(status.description)")
				fail(Error.badResponse(value: status))
				return
			}
			guard let data = data else {
				log(error: "No data was returned")
				fail(Error.noData)
				return
			}
			then(data)
		}
		task.resume()
	}
	
}
