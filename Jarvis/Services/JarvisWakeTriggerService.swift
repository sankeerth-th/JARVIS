import Foundation

protocol JarvisWakeTriggerService {
    func start() async
    func stop() async
}

struct JarvisDeferredWakeTriggerService: JarvisWakeTriggerService {
    func start() async {}
    func stop() async {}
}
