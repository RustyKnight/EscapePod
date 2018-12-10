import Foundation

log(debug: "Lets get this party started...")

DownloadQueue.shared.add(page: URL(string: "http://escapepod.org")!)

if DownloadQueue.shared.queue.operationCount > 0 {
	DownloadQueue.shared.semaphore.wait()
}

log(debug: "Party is done, everyone go home")
