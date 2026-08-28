import TestFlows

@main
enum TranscribeTestFlowsMain {
    static func main() async {
        await TestFlowCLI.run(
            suite: TranscribeFlowSuite.self
        )
    }
}
