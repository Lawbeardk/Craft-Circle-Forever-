# CraftCircle WF 0.5.0

Target: WoW Forever 12.1.5.

## New in 0.5

- **Fixed a Lua error on "Request"** (`attempt to call a nil value` /
  `GetItemInfo`): this client doesn't expose the old global `GetItemInfo`,
  so item-link lookups now fall back to `C_Item.GetItemInfo` automatically.
- Crafters are shown by first name only — no more realm suffix (e.g. the
  `-ClassicBetaPvP` tag) anywhere in the list.
- Dropped the crafter's profession skill number from each row (profession
  name is still shown, just not the numeric skill level).
- Added a "Requires Level" badge per item, plus a min/max level filter and a
  sort button that cycles Name / Level (low→high) / Level (high→low). Level
  data loads in the background the same way icons do, so it may take a
  moment to appear (and to filter/sort correctly) right after opening.
- New UI Scale slider (50%–200%), remembered between sessions.
- A minimap button (drag it around the ring like AtlasLoot's) opens/closes
  the window — no more relying only on the slash command.
- Category tree: the unicode expand arrows that rendered as empty boxes on
  some fonts are now plain `[+]`/`[-]` markers, and each top-level category
  has a small representative icon (sword for Weapon, chestpiece for Armor,
  etc.).

## New in 0.4

- Item icons on every recipe row, with a full item tooltip on hover.
- Recipe names are colored by item quality once their data loads.
- Requesting a craft now whispers a real, clickable item link when available,
  falling back to plain text until the client has cached that item's data.
- Enchanting recipes no longer show a wrong/misleading icon or link — they
  never have a craftable item of their own, so only the recipe name is shown.
- A collapsible category tree on the left (Weapon > weapon type, Armor >
  material · slot, etc.) lets you browse "who can make what" — e.g. Weapon >
  Two-Handed Maces, or Armor > Cloth · Wrist — combined with the existing
  text search.
- Wider window to fit the category pane alongside the results list.

## New in 0.3

- Hash-then-fetch synchronization over the guild addon channel.
- Only compact hash announcements are sent during steady state.
- A missing or changed character record is fetched in bounded chunks.
- Any peer with a validated cached copy may serve it.
- Canonical serialization and post-transfer hash verification.
- Revision checks prevent older copies replacing newer copies.
- Transfer queue, payload limits, chunk limits, deduplication, and expiry.
- Profession cooldown records are included when present in a profession's `cooldowns` list.

## Commands

- `/craftcircle` - toggle catalogue
- `/craftcircle scan` - scan the open profession
- `/craftcircle sync` - announce all locally cached hashes
- `/craftcircle api` - show essential API availability

## How syncing works

Each client announces `character + revision + hash` on login, guild change, scan, or manual sync. A peer only requests data when its hash is missing or different. Transfers are guild broadcasts, allowing all online addon users to update from one response.

## Notes

- All guild members using the addon participate in synchronization.
- Offline characters remain visible from cached copies held by peers.
- Addon traffic is not authenticated. Data from guild peers is schema-checked, size-limited and hash-checked, but a deliberately modified client can still publish false data.
- Cooldowns are synchronized as absolute `readyAt` timestamps without periodic countdown messages. This build preserves and distributes cooldown records, but WF-specific cooldown discovery may require an additional collector once its exact profession cooldown API is confirmed.
