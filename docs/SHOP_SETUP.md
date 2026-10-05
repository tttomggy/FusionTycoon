# Shop setup (Creator Hub)

Harris: every item the shop sells is listed below. Create each one in
**Creator Hub → your experience → Monetization** (Passes, or Developer
Products), using exactly the name, price and description here. Then paste
its id into `src/ReplicatedStorage/Shared/Config/ShopConfig.lua`, in that
item's `Id = 0` line (the `Key` column says which one).

**Icons:** `marketing/shop_icons/<Key>.png` (512 × 512, one per row below;
pass images are shown as a circle, so everything sits inside it).

- **An item with `Id = 0` is hidden in live games.** In Studio it still
  shows in the shop, and tapping it runs a free test grant.
- **Prices are read live from Roblox** (`MarketplaceService:GetProductInfo`).
  The shop never shows a price typed in code, so change a price in Creator
  Hub and the game follows within 10 minutes. The prices below are the
  planned ones; every "SAVE %" and "Worth N R$" is computed from the live
  prices.
- **Restricted** = adds cash or luck. Players whose region restricts paid
  random items (PolicyService) never see or get these.
- **Sales are separate products.** `BoostSale` is the Admin Abuse sale
  version of `Boost`: give it the lower price. It's only sellable while
  Admin Abuse is live, and the shop shows the normal `Boost` price
  struck through next to it.
- Testing without Robux in Studio: type `/shop grant <key>` in chat.

| Key | Type | Name | Price (R$) | Description | Restricted |
|---|---|---|---|---|---|
| `DoubleCash` | Gamepass | 2x Cash | 199 | Double all the cash your lab earns, forever. | no |
| `ExtraPedestals` | Gamepass | +2 Pedestals | 399 | Two more pedestals in your lab: display 6 items instead of 4. | no |
| `VIP` | Gamepass | VIP | 349 | +25% income, a gold VIP tag over your head and in chat, and a gold trim on your lab. | no |
| `AutoFuse` | Gamepass | Auto-Fuse | 149 | A toggle in the Fuse panel: automatically Fuse All (pairs, Common to Epic, never mutated items) whenever new items arrive. | no |
| `LabStyle` | Gamepass | Neon Pink Lab | 99 | A Neon Pink theme for your lab's lights, with pink cash balls. Looks only, no power. | no |
| `Lucky` | Gamepass | Lucky | 299 | x1.5 luck forever (stacks with rebirth luck). Every odds display shows it. | yes |
| `QuickBoost` | Developer Product | Quick Boost | 29 | x2 income for 15 minutes. Stacks by adding time (up to 3 hours banked). | yes |
| `Boost` | Developer Product | Boost | 79 | x2 income for 1 hour. Stacks by adding time (up to 3 hours banked). | yes |
| `BoostSale` | Developer Product | Boost (Admin Abuse sale) | 49 | x2 income for 1 hour, at the Admin Abuse sale price. Only sold during Admin Abuse. | yes |
| `PocketCash` | Developer Product | Pocket Cash | 49 | Cash worth 20 minutes of your lab's income (at least $5,000). | yes |
| `CashCrate` | Developer Product | Cash Crate | 199 | Cash worth 2 hours of your lab's income (at least $50,000). | yes |
| `CashVault` | Developer Product | Cash Vault | 599 | Cash worth 8 hours of your lab's income (at least $250,000). | yes |
| `Overclock` | Developer Product | Server Overclock | 149 | Everyone in the server gets x2 income for 15 minutes. More buys add time, up to 60 minutes. | yes |
| `LuckPotion` | Developer Product | Luck Potion | 49 | x2 luck for 15 minutes. Stacks by adding time (up to 3 hours banked). | yes |
| `SafeFusion1` | Developer Product | Safe Fusion | 25 | One Safe Fusion token: arm it in the Fuse panel, and if that fusion fails you keep every orb. | yes |
| `SafeFusion5` | Developer Product | Safe Fusion x5 | 99 | Five Safe Fusion tokens: arm one in the Fuse panel, and if that fusion fails you keep every orb. | yes |
| `StarterPack` | Developer Product | Starter Pack | 99 | One time only: the Neon Pink Lab look, a 1 hour x2 Boost and Pocket Cash. | yes |
| `OfflineDouble` | Developer Product | Double Offline Cash | 25 | Doubles the cash your lab earned while you were away (the welcome-back card's COLLECT x2). | yes |

After pasting ids: publish, join the live game, open the shop and check
every price shows (an item whose price never loads has a wrong id or type).
