//
//  BulkSigningView.swift
//  Ksign
//
//  Created by Nagata Asami on 11/9/25.
//

import SwiftUI
import NimbleViews
import PhotosUI

struct BulkSigningView: View {
    @FetchRequest(
        entity: CertificatePair.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
        animation: .snappy
    ) private var certificates: FetchedResults<CertificatePair>
    
    private func _selectedCert() -> CertificatePair? {
        guard certificates.indices.contains(_temporaryCertificate) else { return nil }
        return certificates[_temporaryCertificate]
    }
    
    @StateObject private var _optionsManager = OptionsManager.shared
    @State private var _appOptions: [String: Options]
    @State private var _appIcons: [String: UIImage?]
    @State private var _temporaryCertificate: Int
    @State private var _isAltPickerPresenting = false
    @State private var _isFilePickerPresenting = false
    @State private var _isImagePickerPresenting = false
    @State private var _isSigning = false
    @State private var _selectedPhoto: PhotosPickerItem? = nil
    @State private var _selectedAppForIcon: AnyApp?
    @State private var _processedAppsCount = 0
    @State private var _totalAppsToProcess = 0
    @State private var _signedAppUUIDs: [String] = []
    
    @Environment(\.dismiss) private var dismiss
    var apps: [AppInfoPresentable]
    var shouldInstall: Bool

    init(apps: [AppInfoPresentable], shouldInstall: Bool) {
        self.apps = apps
        self.shouldInstall = shouldInstall
        
        let storedCert = UserDefaults.standard.integer(forKey: "feather.selectedCert")
        __temporaryCertificate = State(initialValue: storedCert)
        
        var optionsDict: [String: Options] = [:]
        var iconsDict: [String: UIImage?] = [:]
        let defaultOptions = OptionsManager.shared.options
        
        for app in apps {
            if let uuid = app.uuid {
                optionsDict[uuid] = defaultOptions
                iconsDict[uuid] = nil
            }
        }
        __appOptions = State(initialValue: optionsDict)
        __appIcons = State(initialValue: iconsDict)
    }

    var body: some View {
        NBNavigationView(shouldInstall ? .localized("Signing Options") : .localized("Bulk Signing"), displayMode: .inline) {
            Form {
                _cert()
                
                ForEach(apps, id: \.uuid) { app in
                    if let uuid = app.uuid {
                        Section {
                            _customizationOptions(for: app, options: _bindingOptions(for: uuid), icon: _bindingIcon(for: uuid))
                            _customizationProperties(for: app, options: _bindingOptions(for: uuid))
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    _startSigning()
                } label: {
                    if _isSigning {
                        let current = min(_processedAppsCount + 1, _totalAppsToProcess)
                        NBSheetButton(title: .localized("Signing \(current)/\(apps.count)..."))
                    } else {
                        NBSheetButton(title: shouldInstall ? .localized("Next") : .localized("Start Signing"))
                    }
                }
                .disabled(_isSigning)
            }
            .toolbar {
                NBToolbarButton(role: .dismiss)
                
                NBToolbarButton(
                    .localized("Reset"),
                    style: .text,
                    placement: .topBarTrailing
                ) {
                    for app in apps {
                        if let uuid = app.uuid {
                            _appOptions[uuid] = OptionsManager.shared.options
                            _appIcons[uuid] = nil
                        }
                    }
                }
            }
            .sheet(isPresented: $_isAltPickerPresenting) {
                if let selected = _selectedAppForIcon, let uuid = selected.base.uuid {
                    SigningAlternativeIconView(app: selected.base, appIcon: _bindingIcon(for: uuid), isModifing: .constant(true))
                }
            }
            .sheet(isPresented: $_isFilePickerPresenting) {
                FileImporterRepresentableView(
                    allowedContentTypes:  [.image],
                    onDocumentsPicked: { urls in
                        guard let selectedFileURL = urls.first, let selected = _selectedAppForIcon, let uuid = selected.base.uuid else { return }
                        _appIcons[uuid] = UIImage.fromFile(selectedFileURL)?.resizeToSquare()
                    }
                )
            }
            .photosPicker(isPresented: $_isImagePickerPresenting, selection: $_selectedPhoto)
            .onChange(of: _selectedPhoto) { newValue in
                guard let newValue, let selected = _selectedAppForIcon, let uuid = selected.base.uuid else { return }
                
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data)?.resizeToSquare() {
                        await MainActor.run {
                            _appIcons[uuid] = image
                        }
                    }
                }
            }
            .disabled(_isSigning)
            .animation(.smooth, value: _isSigning)
        }
    }
    
    private func _bindingOptions(for uuid: String) -> Binding<Options> {
        Binding(
            get: { _appOptions[uuid] ?? OptionsManager.shared.options },
            set: { _appOptions[uuid] = $0 }
        )
    }
    
    private func _bindingIcon(for uuid: String) -> Binding<UIImage?> {
        Binding(
            get: { _appIcons[uuid] ?? nil },
            set: { _appIcons[uuid] = $0 }
        )
    }
}

extension BulkSigningView {
    @ViewBuilder
    private func _customizationOptions(for app: AppInfoPresentable, options: Binding<Options>, icon: Binding<UIImage?>) -> some View {
            Menu {
                Button(.localized("Select Alternative Icon")) {
                    _selectedAppForIcon = AnyApp(base: app)
                    _isAltPickerPresenting = true
                }
                Button(.localized("Choose from Files")) {
                    _selectedAppForIcon = AnyApp(base: app)
                    _isFilePickerPresenting = true
                }
                Button(.localized("Choose from Photos")) {
                    _selectedAppForIcon = AnyApp(base: app)
                    _isImagePickerPresenting = true
                }
            } label: {
                if let icon = icon.wrappedValue {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 55, height: 55)
                        .cornerRadius(12)
                } else {
                    FRAppIconView(app: app, size: 55)
                }
            }
            _infoCell(.localized("Name"), desc: options.wrappedValue.appName ?? app.name) {
                SigningPropertiesView(
                    title: .localized("Name"),
                    initialValue: options.wrappedValue.appName ?? (app.name ?? ""),
                    bindingValue: options.appName
                )
            }
            _infoCell(.localized("Identifier"), desc: options.wrappedValue.appIdentifier ?? app.identifier) {
                SigningPropertiesView(
                    title: .localized("Identifier"),
                    initialValue: options.wrappedValue.appIdentifier ?? (app.identifier ?? ""),
                    bindingValue: options.appIdentifier
                )
            }
            _infoCell(.localized("Version"), desc: options.wrappedValue.appVersion ?? app.version) {
                SigningPropertiesView(
                    title: .localized("Version"),
                    initialValue: options.wrappedValue.appVersion ?? (app.version ?? ""),
                    bindingValue: options.appVersion
                )
            }
    }
    

    @ViewBuilder
    private func _cert() -> some View {
        NBSection(.localized("Signing")) {
            if let cert = _selectedCert() {
                NavigationLink {
                    CertificatesView(selectedCert: $_temporaryCertificate)
                } label: {
                    CertificatesCellView(
                        cert: cert
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private func _customizationProperties(for app: AppInfoPresentable, options: Binding<Options>) -> some View {
            DisclosureGroup(.localized("Modify")) {
                NavigationLink(.localized("Existing Dylibs")) {
                    SigningDylibView(
                        app: app,
                        options: options.optional()
                    )
                }
                
                NavigationLink(String.localized("Frameworks & PlugIns")) {
                    SigningFrameworksView(
                        app: app,
                        options: options.optional()
                    )
                }
                #if NIGHTLY || DEBUG
                NavigationLink(String.localized("Entitlements")) {
                    SigningEntitlementsView(
                        bindingValue: options.appEntitlementsFile
                    )
                }
                #endif
                NavigationLink(String.localized("Tweaks")) {
                    SigningTweaksView(
                        options: options
                    )
                }
            }
            
            NavigationLink(String.localized("Properties")) {
                Form { SigningOptionsView(
                    options: options,
                    temporaryOptions: _optionsManager.options
                )}
            .navigationTitle(.localized("Properties"))
        }
    }

    @ViewBuilder
    private func _infoCell<V: View>(_ title: String, desc: String?, @ViewBuilder destination: () -> V) -> some View {
        NavigationLink {
            destination()
        } label: {
            LabeledContent(title) {
                Text(desc ?? .localized("Unknown"))
            }
        }
    }

    private func _startSigning() {
        _processedAppsCount = 0
        _totalAppsToProcess = apps.count
        _signedAppUUIDs = []
        
        let hasCert = _selectedCert() != nil
        
        // If no cert, check if ALL apps are set to adhoc or onlyModify.
        // If at least one app needs a cert and we don't have it -> Error.
        
        var allValid = true
        if !hasCert {
            for app in apps {
                guard let uuid = app.uuid else { continue }
                let opts = _appOptions[uuid] ?? OptionsManager.shared.options
                if !opts.doAdhocSigning && !opts.onlyModify {
                    allValid = false
                    break
                }
            }
        }
        
        guard allValid else {
            UIAlertController.showAlertWithOk(
                title: .localized("No Certificate"),
                message: .localized("Please go to settings and import a valid certificate"),
                isCancel: true
            )
            return
        }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        if shouldInstall {
            let config = BulkInstallConfiguration(
                apps: apps,
                options: _appOptions,
                icons: _appIcons,
                certificate: _selectedCert()
            )
            NotificationCenter.default.post(name: NSNotification.Name("ksign.bulkSignAndInstall"), object: config)
            dismiss()
            return
        }
        
        _isSigning = true

        
        for app in apps {
            guard let uuid = app.uuid else {
                _processedAppsCount += 1
                continue
            }
            
            let opts = _appOptions[uuid] ?? OptionsManager.shared.options
            let icon = _appIcons[uuid] ?? nil
            
            FR.signPackageFile(
                app,
                using: opts,
                icon: icon,
                certificate: _selectedCert()
            ) { [self] newUUID, error in
                if let error {
                    UIAlertController.showAlertWithOk(title: "Error", message: error.localizedDescription)
                } else if let newUUID = newUUID {
                    _signedAppUUIDs.append(newUUID)
                    
                    if opts.removeApp && !app.isSigned {
                        DispatchQueue.main.async {
                            Storage.shared.deleteApp(for: app)
                        }
                    }
                }
                
                _processedAppsCount += 1
                
                if _processedAppsCount == _totalAppsToProcess {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if shouldInstall {
                            NotificationCenter.default.post(name: NSNotification.Name("ksign.bulkSignAndInstall"), object: _signedAppUUIDs)
                        } else {
                            NotificationCenter.default.post(name: NSNotification.Name("ksign.bulkSigningFinished"), object: nil)
                        }
                        dismiss()
                    }
                }
            }
        }

    }
}