#if POURED_PARITY_TESTING
import CryptoKit
import Foundation

struct PouredParityFixtureRecord: Codable, Equatable, Sendable { let id:String; let sourceScenario:String; let dataHash:String; let sessionCount:Int; let canonicalDisposition:String }
struct PouredParityFixture { let snapshot:IslandDebugSnapshot; let record:PouredParityFixtureRecord }

enum PouredParityFixtureCatalog {
    static func resolve(_ configuration:PouredParityConfiguration)->PouredParityFixture {
        let debug:IslandDebugScenario = switch configuration.scenario {
        case .a2WorkingOne:.closed; case .a2mWorkingMany:.closedMultiRunning; case .a3Permission:.closedAttention; case .e1CommandPermission:.approvalCard; case .h1Completed:.completionCard
        }
        let now=Date(timeIntervalSince1970:Double(configuration.epochMilliseconds)/1000)
        let snapshot=debug.snapshot(at:now)
        let payload="poured-v1|\(configuration.scenario.rawValue)|\(debug.rawValue)|\(configuration.seed)|\(configuration.epochMilliseconds)|\(snapshot.sessions.map(\.id).joined(separator:","))"
        let hash=SHA256.hash(data:Data(payload.utf8)).map{String(format:"%02x",$0)}.joined()
        return PouredParityFixture(snapshot:snapshot,record:.init(id:"PouredParityFixtureCatalog.\(configuration.scenario.rawValue)",sourceScenario:debug.rawValue,dataHash:hash,sessionCount:snapshot.sessions.count,canonicalDisposition:"diagnostic-partial"))
    }
}
#endif
