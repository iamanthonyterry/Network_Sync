import Foundation
import Network
import Combine

class DeviceDiscovery: ObservableObject {
    @Published var discoveredDecks: [HyperDeck] = []
    private var browser: NWBrowser?
    
    func startScanning() {
        discoveredDecks.removeAll()
        
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        // FIX 1: Universal static factory constructor for Bonjour descriptors
        let ftpDescriptor = NWBrowser.Descriptor.bonjour(type: "_ftp._tcp", domain: "local.")
        browser = NWBrowser(for: ftpDescriptor, using: parameters)
        
        browser?.stateUpdateHandler = { state in
            print("📡 Discovery Browser State: \(state)")
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            
            for result in results {
                // FIX 2: Safely extract the service metadata name by parsing the endpoint description string
                let endpointDescription = result.endpoint.debugDescription
                
                if endpointDescription.lowercased().contains("hyperdeck") || endpointDescription.lowercased().contains("iso") {
                    // Extract a clean display name out of the string wrapper
                    let cleanName = result.endpoint.cleanServiceName ?? "HyperDeck"
                    self.resolveIP(for: result.endpoint, serviceName: cleanName)
                }
            }
        }
        
        browser?.start(queue: .global(qos: .background))
        print("🔍 Network scanning for HyperDecks initialized...")
    }
    
    func stopScanning() {
        browser?.cancel()
        browser = nil
        print("🛑 Network scanning stopped.")
    }
    
    private func resolveIP(for endpoint: NWEndpoint, serviceName: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            if case .ready = state {
                if let remoteEndpoint = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, _) = remoteEndpoint {
                    
                    // Force extract the raw IPv4 string representation safely
                    let ipAddress = host.interface?.name ?? String(describing: host)
                    let cleanIP = ipAddress.components(separatedBy: "%").first ?? ipAddress
                    
                    DispatchQueue.main.async {
                        if !self.discoveredDecks.contains(where: { $0.ipAddress == cleanIP }) {
                            let newDeck = HyperDeck(
                                name: serviceName,
                                ipAddress: cleanIP,
                                remotePath: "usb/Extreme Pro"
                            )
                            self.discoveredDecks.append(newDeck)
                            print("🎉 Auto-Discovered: \(serviceName) at \(cleanIP)")
                        }
                    }
                }
                connection.cancel()
            }
        }
        connection.start(queue: .global(qos: .background))
    }
}

// MARK: - Extension Helper
extension NWEndpoint {
    /// Safely parses the human-readable service identifier name out of Bonjour string descriptors
    var cleanServiceName: String? {
        let description = self.debugDescription
        // Standard format is usually: name._ftp._tcp.local.
        if let firstDot = description.firstIndex(of: ".") {
            return String(description[..<firstDot])
        }
        return nil
    }
}
