# Group Lock (Project Ascension)

A lightweight World of Warcraft 3.3.5a addon for Project Ascension that automatically declines unwanted group invites based on trust rules, whitelist management, and live roster checks.

<img width="466" height="511" alt="image" src="https://github.com/user-attachments/assets/e5b2c96c-5a1a-4880-907b-7c43fae61291" />


---

## Problem

In social MMO environments, unsolicited party invites can be disruptive. Players need a lightweight way to control who can invite them without manually declining every request.

---

## Solution

Group Lock provides a rule-driven invite filter that automatically accepts trusted sources and declines everyone else.

The addon supports per-character settings, dynamic whitelist management, and integration with in-game social systems such as friends, guild rosters, chat links, and context menus.

---

## Why It Matters

This project demonstrates several engineering patterns beyond game modding:

* Rule-based access control using trusted identity sources
* Event-driven UI behavior within a constrained runtime environment
* Per-user configuration and state persistence
* Multi-surface integration across chat, unit frames, and context menus
* Designing lightweight automation around user experience pain points

Although built as a game addon, the same patterns apply to workflow tooling, allowlist systems, and user-facing automation.

---

## Features

* Auto-decline group invites from untrusted players
* Allow trusted invites from:

  * Friends
  * Guild members
  * Whitelisted players
* Per-character saved settings
* Slash command (`/glock`) configuration panel
* Dynamic UI behavior with ElvUI-aware styling
* Scrollable whitelist manager with inline add/remove controls
* Right-click menu integration for player, unit, raid, and chat roster targets
* Chat-link workflow for rapid whitelisting
* Live synchronization with friends list and guild roster without requiring a reload

---

## Key Design Decisions

* Whitelist-based trust model for predictable behavior
* Per-character persistence to support different play styles or roles
* UI integration across multiple in-game interaction points
* Lightweight automation to reduce repetitive manual actions
* Compatibility-aware behavior for improved user experience in ElvUI environments

---

## Installation

1. Clone or download this repository
2. Copy the `GroupLock` folder into your AddOns directory:

```id="gl1"
Ascension\Interface\AddOns\GroupLock
```

3. Launch the client (or run `/reload`)
4. Ensure **Group Lock** is enabled in the AddOns list

---

## Usage

1. Type `/glock` to open the configuration window
2. Choose whether friends and/or guild members bypass invite blocking
3. Add players to the whitelist by:

   * entering a name manually
   * using the right-click menu option
   * clicking a player name in chat and confirming via the prompt button
4. Remove players from the whitelist using the inline `X` controls

Settings are saved immediately for the current character. Invites from players who do not match the configured trust rules are declined automatically, and a short message is printed to chat for visibility.

---

## Example Use Case

A player wants to avoid unwanted group invites while still allowing trusted social connections through. Group Lock automates that decision process by checking whether the inviter is:

* on the friends list
* in the guild roster
* on the explicit whitelist

If none of those conditions are met, the invite is declined automatically.

---

## Limitations / Tradeoffs

This addon is intentionally lightweight and focused on invite filtering. It does not attempt to provide:

* broader social moderation features
* account-wide trust synchronization
* cross-realm logic beyond what the client environment exposes
* server-side enforcement

Its purpose is to solve one repetitive user problem cleanly and with minimal friction.

---

## Contributing

Comments are included throughout `GroupLock/GroupLock.lua` to explain the main systems and entry points.

Pull requests and issue reports are welcome, especially for:

* bug fixes
* UI improvements
* additional Project Ascension integrations

---

## Author

Jacob Brison
