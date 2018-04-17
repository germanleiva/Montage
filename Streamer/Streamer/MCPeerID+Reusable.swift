/*
 * ==---------------------------------------------------------------------------------==
 *
 *  File            :   MCPeerID+Reusable.swift
 *  Project         :   MCPeerID+Reusable
 *  Author          :   ALEXIS AUBRY RADANOVIC
 *  Creation Date   :   SEPTEMBER 21 2016
 *
 *  License         :   The MIT License (MIT)
 *
 * ==---------------------------------------------------------------------------------==
 */
import MultipeerConnectivity

extension UserDefaults {
    
    ///
    /// The key used to store the local device's PeerID display name.
    ///
    
    fileprivate static let kLocalPeerDisplayNameKey = "kLocalPeerDisplayNameKey"
    
    ///
    /// The key used to store the archive of the local device's PeerID.
    ///
    fileprivate static let kLocalPeerIDKey = "kLocalPeerIDKey"
    
}

extension MCPeerID {
    ///
    /// Returns a reusable PeerID for the local device that will be stable over time.
    ///
    /// If a PeerID with the specified display name is saved, it is unarchived and returned. If a Peer ID with the specified name is not saved, it is created, archived, saved and returned.
    ///
    /// - parameter displayName: The display name for the local peer. The maximum allowable length is 63 bytes in UTF-8 encoding. This parameter may not be nil or an empty string.
    ///
    /// - returns: A PeerID that is stable over time.
    ///
    
    public static func reusableInstance(withDisplayName displayName: String) -> MCPeerID {
        
        let defaults = UserDefaults.standard
        
        func newPeerID() -> MCPeerID {
            let newPeerID = MCPeerID(displayName: displayName)
            newPeerID.save(in: defaults)
            return newPeerID
        }
        
        let oldDisplayName = defaults.string(forKey: UserDefaults.kLocalPeerDisplayNameKey)
        
        if oldDisplayName == displayName {
            
            guard let peerData = defaults.data(forKey: UserDefaults.kLocalPeerIDKey), let peerID = NSKeyedUnarchiver.unarchiveObject(with: peerData) as? MCPeerID else {
                return newPeerID()
            }
            
            return peerID
            
        } else {
            return newPeerID()
        }
        
    }
    
    ///
    /// Archives and saves the current peer identifier in the specified user defaults for later reuse.
    ///
    /// - parameter userDefaults: The user defaults suite where the PeerID and its display name will be stored.
    ///
    private func save(in userDefaults: UserDefaults) {
        
        let peerIDData = NSKeyedArchiver.archivedData(withRootObject: self)
        userDefaults.set(peerIDData, forKey: UserDefaults.kLocalPeerIDKey)
        userDefaults.set(displayName, forKey: UserDefaults.kLocalPeerDisplayNameKey)
        userDefaults.synchronize()
        
    }
    
}
