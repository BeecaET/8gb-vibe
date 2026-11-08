import Foundation
import VibeCore

// 8gbvibe-mcp: MCP server over stdio for AI agents. One process per agent session; kept tiny.
// Reads machine state (the app's status file when fresh, otherwise directly) and coordinates agents through
// files in ~/Library/Application Support/8GB Vibe/agents. Never stops processes or deletes files.
let hub = AgentHub(directory: AgentHub.defaultDirectory)
let hardwareStore = HardwareStore(file: HardwareStore.defaultFile)
var hardwareCache: HardwareInfo?
func hardware() -> HardwareInfo {
    if let h = hardwareCache { return h }
    let h = hardwareStore.loadOrScan().info
    hardwareCache = h
    return h
}
let analyzer = ProcessAnalyzer()

let env = MCPEnvironment(
    hub: hub, pid: getpid(),
    status: {
        if let s = hub.freshStatus() { return s }
        let profile = OptimizationProfile.forHardware(hardware())
        return MachineStatusReader.direct(profile: profile, thresholds: profile.thresholds)
    },
    processes: { analyzer.run() },
    hardware: hardware,
    mcpIdentity: ProcessIdentity.read(pid: getpid())?.0,
    sessionIdentity: ProcessIdentity.read(pid: getppid())?.0)
let server = VibeMCPServer(env: env)

// Keep the registration alive while this process lives, whatever the model does (every 60 seconds).
let heartbeat = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "vn.beeca.8gbvibe.mcp.heartbeat", qos: .utility))
heartbeat.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
heartbeat.setEventHandler { server.autoHeartbeat() }
heartbeat.resume()

server.run()
