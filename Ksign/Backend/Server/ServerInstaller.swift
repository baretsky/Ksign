//
//  Server.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import Vapor
import NIOSSL
import NIOTLS
import SwiftUI

// MARK: - Class
class ServerInstaller: Identifiable, ObservableObject {
	let id = UUID()
	let port = Int.random(in: 4000...8000)
	private var _needsShutdown = false
    
    // Multi-app support
    struct RegisteredApp {
        let app: AppInfoPresentable
        let packageUrl: URL
        let viewModel: InstallerStatusViewModel
    }
    private var _registeredApps: [String: RegisteredApp] = [:]
	
	private let _server: Application

	init() throws {
		self._server = try Self.setupApp(port: port)
		
		try _configureRoutes()
		try _server.server.start()
		_needsShutdown = true
	}
    
    func addApp(_ app: AppInfoPresentable, packageUrl: URL, viewModel: InstallerStatusViewModel) {
        guard let uuid = app.uuid else { return }
        _registeredApps[uuid] = RegisteredApp(app: app, packageUrl: packageUrl, viewModel: viewModel)
    }
	
	deinit {
		_shutdownServer()
	}
		
	private func _configureRoutes() throws {
		_server.get("*") { [weak self] req in
			guard let self else { return Response(status: .badGateway) }
            
            let path = req.url.path
            
            // Check for specific static endpoints first
			if path == displayImageSmallEndpoint.path {
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageSmallData))
            }
            
			if path == displayImageLargeEndpoint.path {
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageLargeData))
            }
            
            // Dynamic handling
            let components = path.split(separator: "/").map(String.init)
            
            if components.count == 2 && components[0] == "install" {
                let uuid = components[1]
                guard _registeredApps[uuid] != nil else { return Response(status: .notFound) }
                
                let itunesLink = self.iTunesLink(for: uuid)
                let html = """
                <html style="background-color: black;">
                <script type="text/javascript">window.location="\(itunesLink)"</script>
                </html>
                """
                return Response(status: .ok, version: req.version, headers: [
                    "Content-Type": "text/html",
                ], body: .init(string: html))
            }
            
            // Dynamic handling based on UUID in filename
            // Expected formats: /:uuid.plist or /:uuid.ipa
            let filename = req.url.path.dropFirst() // Remove leading /
            let ext = (filename as NSString).pathExtension
            let uuid = (filename as NSString).deletingPathExtension
            
            guard let registered = _registeredApps[uuid] else {
                return Response(status: .notFound)
            }
            
            switch ext {
            case "plist":
                self._updateStatus(for: registered.viewModel, .sendingManifest)
                // Generate manifest dynamically for this app
                let manifestData = self.installManifestData(for: registered.app, uuid: uuid)
                return Response(status: .ok, version: req.version, headers: [
                    "Content-Type": "text/xml",
                ], body: .init(data: manifestData))
                
            case "ipa":
                self._updateStatus(for: registered.viewModel, .sendingPayload)
                return req.fileio.streamFile(
                    at: registered.packageUrl.path
                ) { result in
                    self._updateStatus(for: registered.viewModel, .completed(result))
                }
                
            default:
                return Response(status: .notFound)
            }
		}
	}
	
	private func _shutdownServer() {
		guard _needsShutdown else { return }
		
		_needsShutdown = false
		_server.server.shutdown()
		_server.shutdown()
	}
	
	private func _updateStatus(for viewModel: InstallerStatusViewModel, _ newStatus: InstallerStatus) {
		DispatchQueue.main.async {
			viewModel.status = newStatus
		}
	}
		
	static func getServerMethod() -> Int {
		UserDefaults.standard.integer(forKey: "Feather.serverMethod")
	}
	
	static func getIPFix() -> Bool {
		UserDefaults.standard.bool(forKey: "Feather.ipFix")
	}
	
	static func setServerMethod(_ method: Int) {
		UserDefaults.standard.set(method, forKey: "Feather.serverMethod")
	}
	
	static func setIPFix(_ enabled: Bool) {
		UserDefaults.standard.set(enabled, forKey: "Feather.ipFix")
	}
}
