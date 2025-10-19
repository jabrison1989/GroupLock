# Group Lock (Project Ascension)

Group Lock is a lightweight World of Warcraft 3.3.5a addon tailored for Project Ascension. It protects you from unwanted party invites by auto-declining players who are not explicitly trusted.

<img width="466" height="511" alt="image" src="https://github.com/user-attachments/assets/e7db5d87-d5d9-4c42-8f90-1f8266f57f05" />


## Features
- Auto-decline group invites from strangers while letting friends, guildmates, and whitelisted players through.
- Per-character settings (saved variables) so each character can keep a tailored rule set.
- Slash command `/glock` to open a configuration panel that re-skins itself automatically when ElvUI is present.
- Scrollable whitelist manager with inline add/remove controls and dynamic window sizing.
- Right-click context menu item (`Add to GroupLock Whitelist`) for player frames, unit frames, raid frames, and chat roster entries.
- Chat link integration: left-click a player name in chat and press the prompt button to whitelist instantly.
- Live sync with the friends list and guild roster to pick up changes without a reload.

## Installation
1. Download or clone this repository.
2. Copy the `GroupLock` folder into your Ascension AddOns directory, e.g.:
   ```
   Ascension\Interface\AddOns\GroupLock
   ```
3. Launch (or `/reload`) the Ascension client and ensure `Group Lock` is enabled in the AddOns list.

## Usage
- Type `/glock` in-game to open the control window.
- Toggle whether friends and/or guild members bypass the decline rule.
- Add people to the whitelist by:
  - Typing their name into the field and pressing **Add**.
  - Choosing **Add to GroupLock Whitelist** from a player’s right-click menu.
  - Left-clicking a player name in chat and hitting the **Whitelist** button beneath the tooltip.
- Remove entries by clicking the `X` beside their name inside the whitelist list.

Whenever you change options the addon immediately saves them for the current character. Invites from anyone not allowed by your settings are declined automatically, and a short message is printed in chat so you know who was blocked.

## Contributing
Comments have been added throughout `GroupLock/GroupLock.lua` to explain the main systems and entry points. If you would like to contribute, feel free to submit pull requests or file issues describing bugs or enhancements. Suggestions for additional integrations with Ascension-specific systems are very welcome!
