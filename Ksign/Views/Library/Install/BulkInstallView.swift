//
//  BulkInstallView.swift
//  Ksign
//
//  Created by Gemini on 17/01/2026.
//

import SwiftUI
import NimbleViews

struct BulkInstallConfiguration {
    let apps: [AppInfoPresentable]
    let options: [String: Options]
    let icons: [String: UIImage?]
    let certificate: CertificatePair?
}

struct BulkInstallView: View {
    var apps: [AppInfoPresentable]
    var signingContext: BulkInstallConfiguration? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        entity: Signed.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
        animation: .snappy
    ) private var _signedApps: FetchedResults<Signed>
    
    @State private var _serverInstaller: ServerInstaller?
    @State private var _viewModels: [InstallerStatusViewModel] = []
    
    @State private var _currentlyInstallingApp: String? = nil
    @State private var _isInstalling = false
    @State private var _isFinished = false
    @State private var _logs: [String] = []

    var body: some View {
        NBNavigationView(signingContext != nil ? .localized("Sign & Install") : .localized("Bulk Install")) {
            VStack {
                List {
                    Section {
                        ForEach(apps, id: \.uuid) { app in
                            HStack {
                                FRAppIconView(app: app, size: 40)
                                VStack(alignment: .leading) {
                                    Text(app.name ?? .localized("Unknown"))
                                        .font(.headline)
                                    Text(app.version ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if _currentlyInstallingApp == app.uuid {
                                    ProgressView()
                                } else if _hasAppFinished(app) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    
                    if !_logs.isEmpty {
                        Section("Logs") {
                            ForEach(_logs, id: \.self) { log in
                                Text(log)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !_isInstalling {
                    Button {
                        if _isFinished {
                            dismiss()
                        } else {
                            _startInstallation()
                        }
                    } label: {
                        NBSheetButton(title: _isFinished ? .localized("Close") : .localized("Start Installation"))
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .toolbar {
                NBToolbarButton(role: .dismiss)
            }
            .interactiveDismissDisabled(_isInstalling)
            .animation(.smooth, value: _isInstalling)
            .animation(.smooth, value: _isFinished)
        }
    }
    
    private func _hasAppFinished(_ app: AppInfoPresentable) -> Bool {
        guard let index = apps.firstIndex(where: { $0.uuid == app.uuid }),
              _viewModels.indices.contains(index) else { return false }
        
        if case .completed = _viewModels[index].status {
            return true
        }
        return false
    }
    
    private func _startInstallation() {
        _isInstalling = true
        _isFinished = false
        if signingContext != nil {
            _logs.append("Starting batch signing & installation...")
        } else {
            _logs.append("Starting batch installation...")
        }
        
        // Initialize single server instance
        if _serverInstaller == nil {
            do {
                _serverInstaller = try ServerInstaller()
                _logs.append("Installation server started on port \(_serverInstaller!.port)")
            } catch {
                _logs.append("Critical Error: Failed to start server: \(error.localizedDescription)")
                _isInstalling = false
                return
            }
        }
        
        Task {
            for app in apps {
                var appToInstall: AppInfoPresentable? = app
                
                if let config = signingContext {
                     appToInstall = await _sign(app, config: config)
                }
                
                if let targetApp = appToInstall {
                    await _install(targetApp)
                    // Small delay between installs to allow system prompt to appear/animate
                    try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
                }
            }
            
            await MainActor.run {
                _currentlyInstallingApp = nil
                _logs.append("All operations sent. Waiting for transfers to complete...")
            }
            
            // Wait for all transfers to complete
            var allDone = false
            while !allDone {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second check interval
                await MainActor.run {
                    let ongoing = _viewModels.filter {
                        if case .completed = $0.status { return false }
                        if case .broken = $0.status { return false }
                        return true
                    }
                    if ongoing.isEmpty {
                        allDone = true
                    }
                }
            }
            
            await MainActor.run {
                _isInstalling = false
                _isFinished = true
                _logs.append("All operations completed.")
            }
        }
    }
    
    private func _sign(_ app: AppInfoPresentable, config: BulkInstallConfiguration) async -> AppInfoPresentable? {
        guard let uuid = app.uuid else { return nil }
        
        await MainActor.run {
             _currentlyInstallingApp = uuid
            _logs.append("Signing \(app.name ?? "App")...")
        }
        
        let opts = config.options[uuid] ?? OptionsManager.shared.options
        let icon = config.icons[uuid] ?? nil
        
        return await withCheckedContinuation { continuation in
            FR.signPackageFile(
                app,
                using: opts,
                icon: icon,
                certificate: config.certificate
            ) { newUUID, error in
                
                if let error {
                     Task { await MainActor.run {
                        self._logs.append("Error signing \(app.name ?? "App"): \(error.localizedDescription)")
                     }}
                    continuation.resume(returning: nil)
                } else if let newUUID = newUUID {
                    Task { await MainActor.run {
                        self._logs.append("Signed \(app.name ?? "App") successfully.")
                        
                        let req = Signed.fetchRequest()
                        req.predicate = NSPredicate(format: "uuid == %@", newUUID)
                        if let res = try? Storage.shared.context.fetch(req).first {
                            continuation.resume(returning: res)
                        } else {
                            self._logs.append("Error: Could not find signed app in database.")
                            continuation.resume(returning: nil)
                        }
                    }}
                } else {
                     continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func _install(_ app: AppInfoPresentable) async {
        guard let uuid = app.uuid else { return }
        
        await MainActor.run {
            _currentlyInstallingApp = uuid
            _logs.append("Preparing \(app.name ?? "App")...")
        }
        
        let viewModel = InstallerStatusViewModel()
        
        // Keep reference
        await MainActor.run {
             _viewModels.append(viewModel)
        }
        
        do {
            let handler = ArchiveHandler(app: app, viewModel: viewModel)
            try await handler.move()
            let packageUrl = try await handler.archive()
            
            await MainActor.run {
                 _logs.append("Archived \(app.name ?? "App").")
            }

            if let installer = _serverInstaller {
                installer.addApp(app, packageUrl: packageUrl, viewModel: viewModel)
                
                await MainActor.run {
                    viewModel.status = .ready
                    
                    let link = installer.iTunesLink(for: uuid)
                    if let url = URL(string: link) {
                        _logs.append("Requesting install for \(app.name ?? "App")...")
                        UIApplication.shared.open(url)
                    } else {
                        _logs.append("Failed to generate install link for \(app.name ?? "App")")
                    }
                    
                     viewModel.status = .completed(.success(()))
                }
            } else {
                 await MainActor.run {
                    _logs.append("Server not ready for \(app.name ?? "App")")
                 }
            }
            
        } catch {
            await MainActor.run {
                _logs.append("Error installing \(app.name ?? "App"): \(error.localizedDescription)")
            }
        }
    }
}
