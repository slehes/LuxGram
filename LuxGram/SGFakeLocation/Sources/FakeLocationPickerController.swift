import Foundation
import UIKit
import MapKit
import CoreLocation
#if canImport(SGSimpleSettings)
import SGSimpleSettings
#endif
#if canImport(SGStrings)
import SGStrings
#endif
import Display
import TelegramPresentationData

public final class FakeLocationPickerController: ViewController {
    private let presentationData: PresentationData
    private var mapView: MKMapView!
    private var currentPin: MKPointAnnotation?
    private var saveButton: UIButton!
    private var mapTypeControl: UISegmentedControl!
    private var onSave: (() -> Void)?
    
    public init(presentationData: PresentationData, onSave: (() -> Void)? = nil) {
        self.presentationData = presentationData
        self.onSave = onSave
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData))
        
        let lang = presentationData.strings.baseLanguageCode
        self.title = (lang == "ru" ? "Выбор местоположения" : "Pick Location")

        let backItem = UIBarButtonItem(backButtonAppearanceWithTitle: presentationData.strings.Common_Back, target: self, action: #selector(self.backPressed))
        self.navigationItem.leftBarButtonItem = backItem
    }

    @objc private func backPressed() {
        navigateBack()
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        super.loadView()
        
        view.backgroundColor = presentationData.theme.list.plainBackgroundColor
        
        mapView = MKMapView()
        mapView.delegate = self
        mapView.showsUserLocation = false
        mapView.translatesAutoresizingMaskIntoConstraints = false
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:)))
        mapView.addGestureRecognizer(tapGesture)
        
        let lang = presentationData.strings.baseLanguageCode
        let mapTypeItems = [
            (lang == "ru" ? "Обычная" : "Standard"),
            (lang == "ru" ? "Спутник" : "Satellite"),
            (lang == "ru" ? "Гибрид" : "Hybrid")
        ]
        mapTypeControl = UISegmentedControl(items: mapTypeItems)
        mapTypeControl.selectedSegmentIndex = 0
        mapTypeControl.addTarget(self, action: #selector(mapTypeChanged(_:)), for: .valueChanged)
        mapTypeControl.translatesAutoresizingMaskIntoConstraints = false
        
        saveButton = UIButton(type: .system)
        let saveButtonTitle = (lang == "ru" ? "Сохранить" : "Save")
        saveButton.setTitle(saveButtonTitle, for: .normal)
        saveButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        saveButton.backgroundColor = presentationData.theme.list.itemAccentColor
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.layer.cornerRadius = 12
        saveButton.addTarget(self, action: #selector(savePressed), for: .touchUpInside)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(mapView)
        view.addSubview(mapTypeControl)
        view.addSubview(saveButton)
        
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            saveButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            saveButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            saveButton.heightAnchor.constraint(equalToConstant: 50),
            
            mapTypeControl.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            mapTypeControl.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            mapTypeControl.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),
            mapTypeControl.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        view.bringSubviewToFront(saveButton)
        view.bringSubviewToFront(mapTypeControl)
        
        loadSavedLocation()
    }
    
    @objc private func mapTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        addPinAt(coordinate: coordinate)
        
        #if canImport(SGSimpleSettings)
        SGSimpleSettings.shared.fakeLatitude = coordinate.latitude
        SGSimpleSettings.shared.fakeLongitude = coordinate.longitude
        SGSimpleSettings.shared.synchronizeShared()
        #endif
    }
    
    @objc private func mapTypeChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            mapView.mapType = .standard
        case 1:
            mapView.mapType = .satellite
        case 2:
            mapView.mapType = .hybrid
        default:
            break
        }
    }
    
    @objc private func savePressed() {
        #if canImport(SGSimpleSettings)
        if let coordinate = currentPin?.coordinate {
            SGSimpleSettings.shared.fakeLatitude = coordinate.latitude
            SGSimpleSettings.shared.fakeLongitude = coordinate.longitude
            SGSimpleSettings.shared.synchronizeShared()
            onSave?()
        }
        #endif
        navigateBack()
    }

    private func navigateBack() {
        if let nav = self.navigationController, nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        } else {
            self.dismiss(animated: true)
        }
    }
    
    private func loadSavedLocation() {
        #if canImport(SGSimpleSettings)
        let latitude = SGSimpleSettings.shared.fakeLatitude
        let longitude = SGSimpleSettings.shared.fakeLongitude
        
        if latitude != 0.0 && longitude != 0.0 {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            addPinAt(coordinate: coordinate)
            let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
            mapView.setRegion(region, animated: false)
        } else {
            // Default to Moscow if no location is set
            let defaultCoordinate = CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6176)
            let region = MKCoordinateRegion(center: defaultCoordinate, latitudinalMeters: 10000, longitudinalMeters: 10000)
            mapView.setRegion(region, animated: false)
        }
        #else
        let defaultCoordinate = CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6176)
        let region = MKCoordinateRegion(center: defaultCoordinate, latitudinalMeters: 10000, longitudinalMeters: 10000)
        mapView.setRegion(region, animated: false)
        #endif
    }
    
    private func addPinAt(coordinate: CLLocationCoordinate2D) {
        if let existingPin = currentPin {
            mapView.removeAnnotation(existingPin)
        }
        
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        currentPin = annotation
        mapView.addAnnotation(annotation)
    }
}

extension FakeLocationPickerController: MKMapViewDelegate {
    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        }
        
        let identifier = "FakeLocationPin"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        
        if annotationView == nil {
            annotationView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
        } else {
            annotationView?.annotation = annotation
        }
        
        return annotationView
    }
}
