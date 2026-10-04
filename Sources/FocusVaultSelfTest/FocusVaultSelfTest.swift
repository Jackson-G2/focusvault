import Darwin

typealias SelfTestCase = (String, () throws -> Void)

@main
private struct FocusVaultSelfTest {
    static func main() {
        let tests = HostsFileTests.tests +
            ShortFormTests.tests +
            ProductivityTests.tests +
            HostnameTests.tests +
            ManagedMarkerTests.tests +
            TimePolicyTests.tests +
            UnlockGameTests.tests +
            YouTubeGuardTests.tests +
            RefactorRegressionTests.tests


        var failures: [(String, String)] = []
        for (index, test) in tests.enumerated() {
            do {
                try test.1()
                print("PASS [\(index + 1)/\(tests.count)]: \(test.0)")
            } catch {
                let message = String(describing: error)
                failures.append((test.0, message))
                print("FAIL [\(index + 1)/\(tests.count)]: \(test.0) — \(message)")
            }
        }

        if failures.isEmpty {
            print("PASS: all \(tests.count) Vaulty edge-case tests completed")
        } else {
            print("FAIL: \(failures.count) of \(tests.count) Vaulty edge-case tests failed")
            for (name, message) in failures {
                print("  - \(name): \(message)")
            }
            Darwin.exit(EXIT_FAILURE)
        }
    }
}
