# ReuseRankClips — specification

**Tagline:** A clipboard history that learns which items you paste again and again and promotes them to a favorites list.

**Category:** Clipboard

**Inspired by (paid):** PromptClip ($9.99 one-time)

**Frameworks:** SwiftUI, AppKit, CoreGraphics, ApplicationServices, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does and demand. PromptClip is a one-time 9.99 dollar Mac clipboard app that keeps a local history and lets people save prompts, templates and links as permanent snippets, with all data kept on the device. It belongs to a new wave of paid clipboard tools including CleanClip and Clipmighty that compete with free options on being local and one-time priced, and clipboard roundups published in 2026 keep recommending them, which confirms demand for a clipboard that makes repeated text easy to reach.

Our clean-room feature set, distinct from simple history and from numbered slots. The app records text clips and counts how many times each distinct item has been copied or pasted back from the app. When an item reaches a configurable count, default three, it is automatically promoted into a Frequent list that stays above recent history and is never expired. Frequent items show a use count badge and can be renamed with a short label, pinned to the top or demoted. The popup shows two sections: Frequent first, then Recent. Typing filters both. Return pastes the highlighted item into the previous app and increments its count.

UI spec. A MenuBarExtra in window style, about 360 by 460 points, opened by menu bar click or a global hotkey. A search field is on top, then the Frequent section with label, text preview and use count, then the Recent section. Right-click or a trailing button offers Rename, Pin, Demote and Delete. Settings has promotion threshold stepper, history size, how long Recent items are kept, ignore-apps list, paste behavior (paste immediately or copy only), hotkey recorder and launch at login. Empty states read Nothing copied yet and Items you reuse will appear here.

Technical approach. A timer polls NSPasteboard.general changeCount twice a second and reads the string. Items are keyed by a normalized hash of the trimmed text, which lets repeated copies of the same content increment one record instead of adding duplicates. Source app comes from NSWorkspace frontmostApplication and items from ignored apps or marked concealed by password managers are skipped. Records are Codable structs holding text, label, count, lastUsed, pinned and the promoted flag, stored as JSON in Application Support with debounced writes and stored only on this Mac. Pasting restores focus to the previously active app and sends a synthetic Command V CGEvent after placing the text on the pasteboard, which needs Accessibility permission requested through AXIsProcessTrustedWithOptions with an explanation, and without permission the app copies only. A copy that originates from the app itself is tagged by a custom pasteboard type so it counts as a use and not as a new capture. Launch at login uses SMAppService.

Edge cases. Very long text is stored fully but previews are truncated to three lines. Items over one megabyte are ignored. Multiple lines with trailing whitespace changes count as the same item after normalization. Recents expire by age but never Frequent or pinned items. If the Frequent list grows beyond a cap of fifty, the least recently used non-pinned entry is demoted back to Recent. A corrupted store is backed up and replaced with an empty one. The popup must handle rapid copy bursts without freezing, so persistence happens on a background queue.
