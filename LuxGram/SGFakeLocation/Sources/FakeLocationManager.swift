import Foundation
import UIKit
import CoreLocation
#if canImport(SGSimpleSettings)
import SGSimpleSettings
#endif

public final class FakeLocationManager: NSObject {
    public static let shared = FakeLocationManager()
    
    private var locationManagers: NSHashTable<CLLocationManager> = NSHashTable.weakObjects()
    private var periodicUpdateTimer: Foundation.Timer?
    private let timerInterval: TimeInterval = 20.0
    
    private override init() {
        super.init()
        setupAppLifecycleObservers()
    }
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidBecomeActive() {
        startPeriodicUpdates()
    }
    
    @objc private func appDidEnterBackground() {
        stopPeriodicUpdates()
    }
    
    private func startPeriodicUpdates() {
        if periodicUpdateTimer != nil {
            return
        }
        
        #if canImport(SGSimpleSettings)
        guard SGSimpleSettings.shared.fakeLocationEnabled else {
            return
        }
        
        sendFakeLocationToAllManagers()
        
        periodicUpdateTimer = Foundation.Timer.scheduledTimer(
            withTimeInterval: timerInterval,
            repeats: true
        ) { [weak self] _ in
            self?.sendFakeLocationToAllManagers()
        }
        
        if let timer = periodicUpdateTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
        #endif
    }
    
    private func stopPeriodicUpdates() {
        periodicUpdateTimer?.invalidate()
        periodicUpdateTimer = nil
    }
    
    private func sendFakeLocationToAllManagers() {
        #if canImport(SGSimpleSettings)
        guard SGSimpleSettings.shared.fakeLocationEnabled else {
            stopPeriodicUpdates()
            return
        }
        
        let latitude = SGSimpleSettings.shared.fakeLatitude
        let longitude = SGSimpleSettings.shared.fakeLongitude
        
        guard latitude != 0.0 && longitude != 0.0 else {
            return
        }
        
        for manager in locationManagers.allObjects {
            sendFakeLocationToManager(manager)
        }
        #endif
    }
    
    func addLocationManager(_ manager: CLLocationManager) {
        locationManagers.add(manager)
    }
    
    func sendFakeLocationToManager(_ manager: CLLocationManager) {
        #if canImport(SGSimpleSettings)
        guard SGSimpleSettings.shared.fakeLocationEnabled else { return }
        
        let latitude = SGSimpleSettings.shared.fakeLatitude
        let longitude = SGSimpleSettings.shared.fakeLongitude
        
        guard latitude != 0.0 && longitude != 0.0 else { return }
        
        let fakeLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        let fakeLocations = [fakeLocation]
        
        if let delegate = manager.delegate {
            delegate.locationManager?(manager, didUpdateLocations: fakeLocations)
        }
        #endif
    }
}

extension CLLocationManager {
    private static var swizzled = false
    private static var originalStartUpdatingLocationIMP: IMP?
    private static var originalRequestLocationIMP: IMP?
    private static var originalLocationGetterIMP: IMP?
    private static var originalSetDelegateIMP: IMP?
    private static var originalRequestAlwaysAuthorizationIMP: IMP?
    private static var originalRequestWhenInUseAuthorizationIMP: IMP?
    private static var originalAuthorizationStatusGetterIMP: IMP?
    private static var originalStaticAuthorizationStatusIMP: IMP?
    
    public static func swizzleLocationMethods() {
        guard !swizzled else { return }
        swizzled = true
        
        let startUpdatingLocationSelector = #selector(CLLocationManager.startUpdatingLocation)
        let requestLocationSelector = #selector(CLLocationManager.requestLocation)
        let locationGetterSelector = #selector(getter: CLLocationManager.location)
        let setDelegateSelector = #selector(setter: CLLocationManager.delegate)
        let requestAlwaysAuthorizationSelector = #selector(CLLocationManager.requestAlwaysAuthorization)
        let requestWhenInUseAuthorizationSelector = #selector(CLLocationManager.requestWhenInUseAuthorization)
        let authorizationStatusSelector = NSSelectorFromString("authorizationStatus")
        let staticAuthorizationStatusSelector = #selector(CLLocationManager.authorizationStatus)
        
        if let method = class_getInstanceMethod(CLLocationManager.self, startUpdatingLocationSelector),
           let swizzledMethod = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.swizzled_startUpdatingLocation)) {
            originalStartUpdatingLocationIMP = method_getImplementation(method)
            method_exchangeImplementations(method, swizzledMethod)
        }
        
        if #available(iOS 9.0, *) {
            if let method = class_getInstanceMethod(CLLocationManager.self, requestLocationSelector),
               let swizzledMethod = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.swizzled_requestLocation)) {
                originalRequestLocationIMP = method_getImplementation(method)
                method_exchangeImplementations(method, swizzledMethod)
            }
        }
        
        if let method = class_getInstanceMethod(CLLocationManager.self, locationGetterSelector),
           let swizzledMethod = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.swizzled_location)) {
            originalLocationGetterIMP = method_getImplementation(method)
            method_exchangeImplementations(method, swizzledMethod)
        }
        
        if let method = class_getInstanceMethod(CLLocationManager.self, setDelegateSelector),
           let swizzledMethod = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.swizzled_setDelegate(_:))) {
            originalSetDelegateIMP = method_getImplementation(method)
            method_exchangeImplementations(method, swizzledMethod)
        }
        
        if let method = class_getInstanceMethod(CLLocationManager.self, requestAlwaysAuthorizationSelector),
           let swizzledMethod = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.swizzled_requestAlwaysAuthorization)) {
            originalRequestAlwaysAuthorizationIMP = method_getImplementation(method)
            method_exchangeImplementations(method, swizzledMethod)
        }
        
        if let method = class_getInstanceMethod(CLLocationManager.self, requestWhenInUseAuthorizationSelector),
           let swizzledMethod = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.swizzled_requestWhenInUseAuthorization)) {
            originalRequestWhenInUseAuthorizationIMP = method_getImplementation(method)
            method_exchangeImplementations(method, swizzledMethod)
        }
        
        if #available(iOS 14.0, *) {
            if let method = class_getInstanceMethod(CLLocationManager.self, authorizationStatusSelector),
               let swizzledMethod = class_getInstanceMethod(CLLocationManager.self, #selector(CLLocationManager.swizzled_authorizationStatus)) {
                originalAuthorizationStatusGetterIMP = method_getImplementation(method)
                method_exchangeImplementations(method, swizzledMethod)
            }
        }
        
        if let method = class_getClassMethod(CLLocationManager.self, staticAuthorizationStatusSelector),
           let swizzledMethod = class_getClassMethod(CLLocationManager.self, #selector(CLLocationManager.swizzled_staticAuthorizationStatus)) {
            originalStaticAuthorizationStatusIMP = method_getImplementation(method)
            method_exchangeImplementations(method, swizzledMethod)
        }
    }
    
    @objc private func swizzled_setDelegate(_ delegate: CLLocationManagerDelegate?) {
        if let originalIMP = CLLocationManager.originalSetDelegateIMP {
            typealias MethodType = @convention(c) (AnyObject, Selector, CLLocationManagerDelegate?) -> Void
            let methodFunc = unsafeBitCast(originalIMP, to: MethodType.self)
            methodFunc(self, #selector(setter: CLLocationManager.delegate), delegate)
        }
        FakeLocationManager.shared.addLocationManager(self)
        
        #if canImport(SGSimpleSettings)
        if SGSimpleSettings.shared.fakeLocationEnabled {
            let latitude = SGSimpleSettings.shared.fakeLatitude
            let longitude = SGSimpleSettings.shared.fakeLongitude
            if latitude != 0.0 && longitude != 0.0 {
                self.stopUpdatingLocation()
                FakeLocationManager.shared.sendFakeLocationToManager(self)
            }
        }
        #endif
    }
    
    @objc private func swizzled_startUpdatingLocation() {
        FakeLocationManager.shared.addLocationManager(self)
        
        #if canImport(SGSimpleSettings)
        if SGSimpleSettings.shared.fakeLocationEnabled {
            let latitude = SGSimpleSettings.shared.fakeLatitude
            let longitude = SGSimpleSettings.shared.fakeLongitude
            if latitude != 0.0 && longitude != 0.0 {
                FakeLocationManager.shared.sendFakeLocationToManager(self)
                return
            }
        }
        #endif
        
        if let originalIMP = CLLocationManager.originalStartUpdatingLocationIMP {
            typealias MethodType = @convention(c) (AnyObject, Selector) -> Void
            let methodFunc = unsafeBitCast(originalIMP, to: MethodType.self)
            methodFunc(self, #selector(startUpdatingLocation))
        }
    }
    
    @available(iOS 9.0, *)
    @objc private func swizzled_requestLocation() {
        #if canImport(SGSimpleSettings)
        if SGSimpleSettings.shared.fakeLocationEnabled {
            let latitude = SGSimpleSettings.shared.fakeLatitude
            let longitude = SGSimpleSettings.shared.fakeLongitude
            if latitude != 0.0 && longitude != 0.0 {
                FakeLocationManager.shared.sendFakeLocationToManager(self)
                return
            }
        }
        #endif
        
        if let originalIMP = CLLocationManager.originalRequestLocationIMP {
            typealias MethodType = @convention(c) (AnyObject, Selector) -> Void
            let methodFunc = unsafeBitCast(originalIMP, to: MethodType.self)
            methodFunc(self, #selector(requestLocation))
        }
    }
    
    @objc private func swizzled_location() -> CLLocation? {
        #if canImport(SGSimpleSettings)
        if SGSimpleSettings.shared.fakeLocationEnabled {
            let latitude = SGSimpleSettings.shared.fakeLatitude
            let longitude = SGSimpleSettings.shared.fakeLongitude
            if latitude != 0.0 && longitude != 0.0 {
                return CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    altitude: 0,
                    horizontalAccuracy: 10,
                    verticalAccuracy: 10,
                    timestamp: Date()
                )
            }
        }
        #endif
        
        if let originalIMP = CLLocationManager.originalLocationGetterIMP {
            typealias MethodType = @convention(c) (AnyObject, Selector) -> CLLocation?
            let methodFunc = unsafeBitCast(originalIMP, to: MethodType.self)
            return methodFunc(self, #selector(getter: CLLocationManager.location))
        }
        
        return nil
    }
    
    @objc private func swizzled_requestAlwaysAuthorization() {
        if let originalIMP = CLLocationManager.originalRequestAlwaysAuthorizationIMP {
            typealias MethodType = @convention(c) (AnyObject, Selector) -> Void
            let methodFunc = unsafeBitCast(originalIMP, to: MethodType.self)
            methodFunc(self, #selector(requestAlwaysAuthorization))
        }
    }
    
    @objc private func swizzled_requestWhenInUseAuthorization() {
        if let originalIMP = CLLocationManager.originalRequestWhenInUseAuthorizationIMP {
            typealias MethodType = @convention(c) (AnyObject, Selector) -> Void
            let methodFunc = unsafeBitCast(originalIMP, to: MethodType.self)
            methodFunc(self, #selector(requestWhenInUseAuthorization))
        }
    }
    
    @available(iOS 14.0, *)
    @objc private func swizzled_authorizationStatus() -> CLAuthorizationStatus {
        if let originalIMP = CLLocationManager.originalAuthorizationStatusGetterIMP {
            typealias MethodType = @convention(c) (AnyObject, Selector) -> CLAuthorizationStatus
            let methodFunc = unsafeBitCast(originalIMP, to: MethodType.self)
            return methodFunc(self, NSSelectorFromString("authorizationStatus"))
        }
        return .notDetermined
    }
    
    @objc private static func swizzled_staticAuthorizationStatus() -> CLAuthorizationStatus {
        if let originalIMP = CLLocationManager.originalStaticAuthorizationStatusIMP {
            typealias MethodType = @convention(c) (AnyClass, Selector) -> CLAuthorizationStatus
            let methodFunc = unsafeBitCast(originalIMP, to: MethodType.self)
            return methodFunc(CLLocationManager.self, #selector(CLLocationManager.authorizationStatus))
        }
        return .notDetermined
    }
}
