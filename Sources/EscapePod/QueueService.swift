//
//  File.swift
//  Basic
//
//  Created by Shane Whitehead on 10/12/18.
//

import Foundation
import SwiftSoup

var downloadPath: Path = Path.userHome + "EscapePod"

class QueueService: NSObject {
	static let shared = QueueService()
	
	var semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
	var count = 0
	
	var pageQueue: OperationQueue = {
		let queue = OperationQueue()
		queue.qualityOfService = .userInitiated
		queue.maxConcurrentOperationCount = 1
		
		return queue
	}()

	var downloadQueue: OperationQueue = {
		let queue = OperationQueue()
		queue.qualityOfService = .userInitiated
		queue.maxConcurrentOperationCount = 4
		
		return queue
	}()

	func add(page: URL, initial: Bool = false) {
		count += 1
		pageQueue.addOperation(PageOperation(url: page, initial: initial))
	}
	
	func download(_ url: URL) {
		count += 1
		downloadQueue.addOperation(DownloadOperation(url: url))
	}
	
	func completed(operation: Operation) {
		count -= 1
		DispatchQueue.global().async {
			Thread.sleep(forTimeInterval: 1.0)
			self.checkCompleted()
		}
	}
	
	@objc func checkCompleted() {
		log(debug: "\(count) remaining operations")
		guard count == 0 else {
			return
		}
		semaphore.signal()
	}
}

struct MetaData: Codable {
	var role: String
	var value: String
}

class PageOperation: Operation {
	
	let url: URL
	let initial: Bool
	
	init(url: URL, initial: Bool) {
		self.url = url
		self.initial = initial
	}
	
	enum Error: Swift.Error {
		case unknownResponse
		case badResponse(value: HTTPURLResponse)
		case noData
	}
	
	override func main() {
		guard !isCancelled else { return }
		Thread.sleep(forTimeInterval: 5.0)
		log("")
		log(debug: "Download page from \(url)")
		read(url: url, then: { (data) in
			defer {
				log(debug: "Completed processing \(self.url)")
				log("")
				QueueService.shared.completed(operation: self)
			}
			log(debug: "Parse page result from \(self.url)")
			guard let text = String(data: data, encoding: .utf8) else {
				log(error: "Could not parse result from \(self.url) to text")
				return
			}
			do {
				let doc: Document = try SwiftSoup.parse(text)
				
				guard let elements = try doc.body()?.select("div main div article div header") else {
					return
				}
				var downloaded: [String] = []
				var ignored: [String] = []
				for element in elements {
					let linkElement = try element.select("h3 a")
					let text = try linkElement.text()
					
					let downloadElement = try element.select("div div p a.powerpress_link_d")
					let href = try downloadElement.attr("href")
					
					guard let url = URL(string: href) else {
						ignored.append(text)
						continue
					}
					downloaded.append(text)
					
					//QueueService.shared.download(url)
					
					// Write this out as json
					var metaData: [MetaData] = []
					metaData.append(MetaData(role: "title", value: text))
					let metaElements = try element.select("div ul li")
					for metaElement in metaElements {
						let spanElement = try metaElement.select("span")
						let anchorElement = try metaElement.select("a")
						let role = try spanElement.text()
						
						//let roleHref = try anchorElement.attr("href")
						let roleText = try anchorElement.text()
						
						guard !role.isEmpty else {
							continue
						}
						metaData.append(MetaData(role: role, value: roleText))
					}
					
					let name = url.deletingPathExtension().lastPathComponent + ".json"
					let destPath = TextFile(path: downloadPath + name)

					let encoder = JSONEncoder()
					encoder.outputFormatting = .prettyPrinted

					let data = try encoder.encode(metaData)
					guard let metaText = String(data: data, encoding: .utf8) else {
						log(error: "Could not convert meta data to text")
						return
					}
//					log(debug: "Write \(metaText)")
//					log(debug: "to \(destPath)")

					try metaText |> destPath
				}
				
				for download in downloaded {
					log("Download \(download)")
				}
				for ignore in ignored {
					log(warning: "Ignored \(ignore)")
				}

				guard self.initial else {
					return
				}
				
				guard let pageElements = try doc.body()?.select("div main div div a") else {
					log(debug: "No more pages")
					return
				}
				var maxPages = 0
				for pageElement in pageElements {
					guard try pageElement.attr("class") == "page-numbers" else {
						continue
					}
					guard let page = Int(try pageElement.text()) else {
						continue
					}
					maxPages = max(page, maxPages)
				}
				log(debug: "maxPages = \(maxPages)")
				for page in 2...maxPages {
					guard let url = URL(string: "/page/\(page)", relativeTo: self.url) else {
						continue
					}
			    QueueService.shared.add(page: url)
				}
			} catch let error {
				log(error: error.localizedDescription)
			}
		}) { (error) in
			log(error: error.localizedDescription)
			Thread.sleep(forTimeInterval: 1.0)
			QueueService.shared.completed(operation: self)
		}
	}
	
	func read(url: URL, then: @escaping (Data) -> Void, fail: @escaping (Swift.Error) -> Void) {
		let sessionConfig = URLSessionConfiguration.default
		let session = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		
		let task = session.dataTask(with: request) { (data: Data?, response: URLResponse?, error: Swift.Error?) in
			//log(debug: "Download request for \(url) completed")
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

class DownloadOperation: Operation {
	
	enum Error: Swift.Error {
		case unknownResponse
		case badResponse(value: HTTPURLResponse)
		case invalidSourceFile
		case copyFailed(error: Swift.Error)
		case couldNotCreateOutputPath(error: Swift.Error)
	}
	
	let url: URL
	
	init(url: URL) {
		self.url = url
	}
	
	override func main() {
		guard !isCancelled else {
			return
		}
		Thread.sleep(forTimeInterval: 5)
		download(then: {
			QueueService.shared.completed(operation: self)
		}) { (error) in
			log(error: error.localizedDescription)
			QueueService.shared.completed(operation: self)
		}
	}
	
	func download(then: @escaping () -> Void, fail: @escaping (Swift.Error) -> Void) {
		
		let sessionConfig = URLSessionConfiguration.default
		let session = URLSession(configuration: sessionConfig)
		
		let request = URLRequest(url: url)
		
		let name = url.lastPathComponent
		let destPath = downloadPath + name
		
		log(debug: "Download from \(url)")
		let task = session.downloadTask(with: request) { (tempLocalUrl, response, error) in
			if let error = error {
				fail(error)
				return
			}
			guard let status = response as? HTTPURLResponse else {
				fail(Error.unknownResponse)
				return
			}
			guard status.statusCode == 200 else {
				fail(Error.badResponse(value: status))
				return
			}
			guard let tempLocalUrl = tempLocalUrl, let tempFile = Path(url: tempLocalUrl) else {
				fail(Error.invalidSourceFile)
				return
			}

			do {
				if destPath.exists {
					try destPath.deleteFile()
				}
				
//				log(debug: "Move\n     \(tempFile.absolute)\n  to \(destPath.absolute)")
				try tempFile.moveFile(to: destPath)
				log("\(self.url) downloaded to \(destPath.absolute)")
				then()
			} catch let error {
				fail(Error.copyFailed(error: error))
			}
		}
		task.resume()
	}
}
