//
//  BulkInstallProgressView.swift
//  Ksign
//
//  Created by Nagata Asami on 27/1/26.
//

import SwiftUI
import NimbleViews

struct BulkInstallProgressView: View {
    var app: AppInfoPresentable
    @StateObject var viewModel = InstallerStatusViewModel()
    
    #if SERVER
    @AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
    @StateObject var installer: ServerInstaller
    @State private var _isWebviewPresenting = false
    #endif
    
    init(app: AppInfoPresentable) {
        self.app = app
        let viewModel = InstallerStatusViewModel()
        self._viewModel = StateObject(wrappedValue: viewModel)
        #if SERVER
        self._installer = StateObject(wrappedValue: try! ServerInstaller(app: app, viewModel: viewModel))
        #endif
    }
    
    var body: some View {
        VStack {
            InstallProgressView(app: app, viewModel: viewModel)
            _status()
        }
        #if SERVER
        .sheet(isPresented: $_isWebviewPresenting) {
            SafariRepresentableView(url: installer.pageEndpoint).ignoresSafeArea()
        }
        .onReceive(viewModel.$status) { newStatus in
            if case .ready = newStatus {
                if _serverMethod == 0 {
                    UIApplication.shared.open(URL(string: installer.iTunesLink)!)
                } else if _serverMethod == 1 {
                    _isWebviewPresenting = true
                }
            }
            
            if case .sendingPayload = newStatus, _serverMethod == 1 {
                _isWebviewPresenting = false
            }
            
            if case .completed = newStatus {
                BackgroundAudioManager.shared.stop()
            }
        }
        #endif
        .onAppear(perform: _install)
        .onAppear {
            BackgroundAudioManager.shared.start()
        }
        .onDisappear {
            BackgroundAudioManager.shared.stop()
        }
    }
    
    private func _install() {
        Task.detached {
            do {
                let handler = await ArchiveHandler(app: app, viewModel: viewModel)
                try await handler.move()
                
                let packageUrl = try await handler.archive()
                
                #if SERVER
                await MainActor.run {
                    installer.packageUrl = packageUrl
                    viewModel.status = .ready
                }
                #elseif IDEVICE
                let handler = await ConduitInstaller(viewModel: viewModel)
                try await handler.install(at: packageUrl)
                #endif
                
            } catch {
                await MainActor.run {
                    #if IDEVICE
                    HeartbeatManager.shared.start(true)
                    #endif
                    
                }
            }
        }
    }
    
    @ViewBuilder
    private func _status() -> some View {
        Text(viewModel.statusLabel)
            .font(.caption)
            .minimumScaleFactor(0.5)
            .animation(.smooth, value: viewModel.statusImage)
            .lineLimit(1)
    }
}
