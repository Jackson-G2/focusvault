enum CLIUsage {
    static func printUsage() {
        print(
            """
            Vaulty — a free macOS website blocker
            Vault in. Get work done.

            Short commands:
              block      Engage the YouTube blocker.
              unblock    Open the YouTube blocker.
              status     Show whether the YouTube blocker is engaged.
              short-form Engage the separate short-form blocker.
              guard       Inspect or remove the installed automatic lock guard.
              allowlist   Show the fallback YouTube channels used before native pairing.
              version    Print the installed version.

            Usage:
              vaulty block [--domain DOMAIN ...] [--hosts-file PATH] [--dry-run]
              vaulty unblock [--hosts-file PATH]
              vaulty status [--hosts-file PATH]
              vaulty short-form block [--hosts-file PATH]
              vaulty short-form unblock [--hosts-file PATH]
              vaulty short-form status [--hosts-file PATH]
              vaulty guard status
              sudo vaulty guard uninstall [--user-home /Users/name]
              vaulty allowlist
              vaulty version

            The YouTube blocker manages its own marked section in /etc/hosts.
            The separate short-form blocker manages a second independent section and
            covers TikTok, Instagram, YouTube, and Facebook hosts completely; the
            browser companion adds path-level Reels/Shorts filtering when needed.
            Editing /etc/hosts normally requires sudo:

              sudo vaulty block
              vaulty status
              sudo vaulty unblock
              sudo vaulty short-form block
              vaulty short-form status
              sudo vaulty short-form unblock

            The legacy `focusvault` command remains a compatibility alias.
            --hosts-file is intended for safe testing or a separate hosts file.
            """
        )
    }
}
