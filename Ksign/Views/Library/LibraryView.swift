//
//  ContentView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import CoreData
import NimbleViews

struct BulkSigningSession: Identifiable {
    let id = UUID()
    let apps: [AppInfoPresentable]
    let shouldInstall: Bool
}

// MARK: - View
struct LibraryView: View {
	@StateObject private var _downloadManager = DownloadManager.shared
	
	    @State private var _selectedInfoAppPresenting: AnyApp?
		@State private var _selectedSigningAppPresenting: AnyApp?
		@State private var _selectedInstallAppPresenting: AnyApp?
		@State private var _selectedAppDylibsPresenting: AnyApp?
		@State private var _bulkSigningSession: BulkSigningSession?
		@State private var _isBulkInstallPresenting = false
		@State private var _isImportingPresenting = false
		@State private var _isDownloadingPresenting = false
	
		@State private var _alertDownloadString: String = "" // for _isDownloadingPresenting
		@State private var _searchText = ""
		@State private var _selectedTab: Int = 0 // 0 for Downloaded, 1 for Signed
		
	    // MARK: Bulk Install
	    @State private var _bulkInstallConfig: BulkInstallConfiguration? = nil
	// MARK: Edit Mode
	@State private var _isEditMode = false
	@State private var _selectedApps: Set<String> = []
	
	@Namespace private var _namespace
	
	private func _filterAndSortApps<T>(from apps: FetchedResults<T>) -> [T] where T: NSManagedObject {
		apps.filter {
			_searchText.isEmpty ||
			(($0.value(forKey: "name") as? String)?.localizedCaseInsensitiveContains(_searchText) ?? false)
		}
	}
	
	private var _filteredSignedApps: [Signed] {
		_filterAndSortApps(from: _signedApps)
	}
	
	private var _filteredImportedApps: [Imported] {
		_filterAndSortApps(from: _importedApps)
	}
	
	// MARK: Fetch
	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
		animation: .snappy
	) private var _signedApps: FetchedResults<Signed>
	
	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _importedApps: FetchedResults<Imported>
	
	// MARK: Body
    var body: some View {
		NBNavigationView(.localized("Library")) {
			VStack(spacing: 0) {
				Picker("", selection: $_selectedTab) {
					Text(.localized("Downloaded Apps")).tag(0)
					Text(.localized("Signed Apps")).tag(1)
				}
				.pickerStyle(SegmentedPickerStyle())
				.padding(.horizontal)
				.padding(.vertical, 8)
                .onChange(of: _selectedTab) { _ in
                    _selectedApps.removeAll()
                }
				
				NBListAdaptable {
					if _selectedTab == 0 {
						NBSection(
							.localized("Downloaded Apps"),
							secondary: _filteredImportedApps.count.description
						) {
							ForEach(_filteredImportedApps, id: \.uuid) { app in
								LibraryCellView(
									app: app,
									selectedInfoAppPresenting: $_selectedInfoAppPresenting,
									selectedSigningAppPresenting: $_selectedSigningAppPresenting,
									selectedInstallAppPresenting: $_selectedInstallAppPresenting,
									selectedAppDylibsPresenting: $_selectedAppDylibsPresenting,
									isEditMode: $_isEditMode,
									selectedApps: $_selectedApps
								)
								.compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
							}
						}
					} else {
						NBSection(
							.localized("Signed Apps"),
							secondary: _filteredSignedApps.count.description
						) {
							ForEach(_filteredSignedApps, id: \.uuid) { app in
								LibraryCellView(
									app: app,
									selectedInfoAppPresenting: $_selectedInfoAppPresenting,
									selectedSigningAppPresenting: $_selectedSigningAppPresenting,
									selectedInstallAppPresenting: $_selectedInstallAppPresenting,
									selectedAppDylibsPresenting: $_selectedAppDylibsPresenting,
									isEditMode: $_isEditMode,
									selectedApps: $_selectedApps
								)
								.compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
							}
						}
					}
				}
			}
			.searchable(text: $_searchText, placement: .platform())
            .overlay {
                if
                    _filteredSignedApps.isEmpty,
                    _filteredImportedApps.isEmpty
                {
                    if #available(iOS 17, *) {
                        ContentUnavailableView {
                            Label(.localized("No Apps"), systemImage: "questionmark.app.fill")
                        } description: {
                            Text(.localized("Get started by importing your first IPA file."))
                        } actions: {
                            Menu {
                                _importActions()
                            } label: {
                                Text("Import").bg()
                            }
                        }
                    }
                }
            }
			.toolbar {
				if _isEditMode {
					ToolbarItem(placement: .topBarLeading) {
						Button {
							_toggleEditMode()
						} label: {
							NBButton(.localized("Done"), systemImage: "", style: .text)
						}
					}
					
					ToolbarItemGroup(placement: .topBarTrailing) {
                        if _selectedTab == 1 {
                            Button {
                                _isBulkInstallPresenting = true
                            } label: {
                                NBButton(.localized("Install"), systemImage: "square.and.arrow.down", style: .icon)
                            }
                            .disabled(_selectedApps.isEmpty)
                        }
                        
                        if _selectedTab == 0 {
                            Menu {
                                Button {
                                    _bulkSigningSession = BulkSigningSession(
                                        apps: _selectedApps.compactMap { id in
                                            (_importedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
                                            ?? (_signedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
                                        },
                                        shouldInstall: false
                                    )
                                } label: {
                                    Label(.localized("Sign Only"), systemImage: "signature")
                                }
                                
                                Button {
                                    _bulkSigningSession = BulkSigningSession(
                                        apps: _selectedApps.compactMap { id in
                                            (_importedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
                                            ?? (_signedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
                                        },
                                        shouldInstall: true
                                    )
                                } label: {
                                    Label(.localized("Sign & Install"), systemImage: "square.and.arrow.down")
                                }
                            } label: {
                                NBButton(.localized("Sign"), systemImage: "signature", style: .icon)
                            }
                            .disabled(_selectedApps.isEmpty)
                        }
						
						Button {
							_bulkDeleteSelectedApps()
						} label: {
							NBButton(.localized("Delete"), systemImage: "trash", style: .icon)
						}
						.disabled(_selectedApps.isEmpty)
					}
				} else {
					ToolbarItem(placement: .topBarLeading) {
						Button {
							_toggleEditMode()
						} label: {
							NBButton(.localized("Edit"), systemImage: "", style: .text)
						}
					}
					
					NBToolbarMenu(
						systemImage: "plus",
						style: .icon,
						placement: .topBarTrailing
					) {
                        _importActions()
                    }
				}
			}
			.sheet(item: $_selectedInfoAppPresenting) { app in
				LibraryInfoView(app: app.base)
			}
			.sheet(item: $_selectedInstallAppPresenting) { app in
				InstallPreviewView(app: app.base, isSharing: app.archive)
					.presentationDetents([.height(200)])
					.presentationDragIndicator(.visible)
					.compatPresentationRadius(21)
			}
			.fullScreenCover(item: $_selectedSigningAppPresenting) { app in
				SigningView(app: app.base, signAndInstall: app.signAndInstall)
					.compatNavigationTransition(id: app.base.uuid ?? "", ns: _namespace)
			}
			.fullScreenCover(item: $_selectedAppDylibsPresenting) { app in
                DylibsView(app: app.base)
					.compatNavigationTransition(id: app.base.uuid ?? "", ns: _namespace)
			}
			.fullScreenCover(item: $_bulkSigningSession) { session in
				BulkSigningView(
                    apps: session.apps,
                    shouldInstall: session.shouldInstall
                )
				.compatNavigationTransition(id: _selectedApps.joined(separator: ","), ns: _namespace)
				.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ksign.bulkSigningFinished"))) { notification in
					_toggleEditMode()
					_selectedTab = 1
				}
			}
            .sheet(isPresented: $_isBulkInstallPresenting) {
                BulkInstallView(
                    apps: _bulkInstallConfig?.apps ?? _selectedApps.compactMap { id in
                        (_importedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
                        ?? (_signedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
                    },
                    signingContext: _bulkInstallConfig
                )
            }
            .onChange(of: _isBulkInstallPresenting) { isPresented in
                if !isPresented {
                    _bulkInstallConfig = nil
                }
            }
			.sheet(isPresented: $_isImportingPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes:  [.ipa, .tipa],
					allowsMultipleSelection: true,
					onDocumentsPicked: { urls in
						guard !urls.isEmpty else { return }
						
						for ipas in urls {
							let id = "FeatherManualDownload_\(UUID().uuidString)"
							let dl = _downloadManager.startArchive(from: ipas, id: id)
							_downloadManager.handlePachageFile(url: ipas, dl: dl) { err in
								if let error = err {
									UIAlertController.showAlertWithOk(title: "Error", message: .localized("Whoops!, something went wrong when extracting the file. \nMaybe try switching the extraction library in the settings?"))
								}
							}
						}
					}
				)
			}
			.alert(.localized("Import from URL"), isPresented: $_isDownloadingPresenting) {
				TextField(.localized("URL"), text: $_alertDownloadString)
				Button(.localized("Cancel"), role: .cancel) {
					_alertDownloadString = ""
				}
				Button(.localized("OK")) {
					if let url = URL(string: _alertDownloadString) {
						_ = _downloadManager.startDownload(from: url, id: "FeatherManualDownload_\(UUID().uuidString)")
					}
				}
			}
			.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("feather.installApp"))) { notification in
                if let app = _signedApps.first {
                    _selectedInstallAppPresenting = AnyApp(base: app)
				}
			}
			.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ksign.bulkSignAndInstall"))) { notification in
				_toggleEditMode()
				_selectedTab = 1
                
                if let config = notification.object as? BulkInstallConfiguration {
                    self._bulkInstallConfig = config
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self._isBulkInstallPresenting = true
                    }
                } else if let signedUUIDs = notification.object as? [String] {
                    self._bulkInstallConfig = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let newApps = self._signedApps.filter { app in
                            guard let uuid = app.uuid else { return false }
                            return signedUUIDs.contains(uuid)
                        }
                        self._selectedApps = Set(newApps.compactMap { $0.uuid })
                        self._isBulkInstallPresenting = true
                    }
                }
			}
        }
    }
}

extension LibraryView {
    @ViewBuilder
    private func _importActions() -> some View {
        Button(.localized("Import from Files"), systemImage: "folder") {
            _isImportingPresenting = true
        }
        Button(.localized("Import from URL"), systemImage: "globe") {
            _isDownloadingPresenting = true
        }
    }
}


// MARK: - Extension: View (Edit Mode Functions)
extension LibraryView {
	private func _toggleEditMode() {
		withAnimation(.easeInOut(duration: 0.3)) {
			_isEditMode.toggle()
			if !_isEditMode {
				_selectedApps.removeAll()
			}
		}
	}
	
	private func _bulkDeleteSelectedApps() {
		let appsToDelete = _selectedApps
		
		withAnimation(.easeInOut(duration: 0.5)) {
			for appUUID in appsToDelete {
				if let signedApp = _signedApps.first(where: { $0.uuid == appUUID }) {
					Storage.shared.deleteApp(for: signedApp)
				} else if let importedApp = _importedApps.first(where: { $0.uuid == appUUID }) {
					Storage.shared.deleteApp(for: importedApp)
				}
			}
		}
		
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
			_selectedApps.removeAll()
			 _toggleEditMode()
		}
	}
}
