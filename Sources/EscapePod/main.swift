import Foundation

log(debug: "Lets get this party started...")

do {
	if !downloadPath.exists {
		log(debug: "Make directory \(downloadPath.absolute)")
		try downloadPath.createDirectory()
	}

	DownloadQueue.shared.add(page: URL(string: "http://escapepod.org")!, initial: true)

	if DownloadQueue.shared.queue.operationCount > 0 {
		DownloadQueue.shared.semaphore.wait()
	}

	log(debug: "Party is done, everyone go home")
} catch let error {
	log(error: error.localizedDescription)
}
