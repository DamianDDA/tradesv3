# Bright Falls RP Prediction Exchange

A RedM resource for VORP. Players wager their active character's in-game cash on staff-created, two-outcome markets. The exchange uses a red-and-black in-game interface.

## Install

1. Place the `bf_markets` folder in your server's resources directory. Keep that folder name so the ledger stays under the same resource namespace.
2. Add the following after the VORP startup entries in `server.cfg`. Market management is granted to the Cfx `group.superadmin` principal. On an existing install, remove the earlier `add_ace group.admin bfmarkets.manage allow` line and restart the server, or revoke that grant in the live console with `remove_ace group.admin bfmarkets.manage allow` after saving the new configuration.
   
   ```cfg
   add_ace group.superadmin bfmarkets.manage allow
   ensure bf_markets
   ```
   
3. If your staff member is not already in the group, map their Cfx identifier to your staff principal with `add_principal identifier.license:YOUR_LICENSE group.superadmin`. A VORP group alone does not grant this ACE.
4. Join with an active VORP character. Run `/marketadmin` to publish your first market. Players open the exchange with `/markets`. Escape closes it.

The resource uses the VORP core export and character cash methods for currency type 0. It needs no additional SQL import. Check config.lua for command names, branding, wager limits, and capacity.

## Update an existing bf_trades installation

Copy the three files from this archive’s `bf_markets/ui/` into the running resource’s `bf_trades/ui/` folder. Keep the existing folder name for the saved ledger. For this setup use `ensure bf_trades` in server.cfg.

## Fix the RedM prerelease warning

If you already installed this resource under another folder name, copy only the updated `fxmanifest.lua` into that existing folder and run `refresh` followed by `ensure YOUR_RESOURCE_NAME` in the server console. Keep the existing folder name to retain its saved ledger.

## Run a market

- Staff provide the question, the two outcomes, how the result will be determined, and the time until wagering closes.
- Players select an outcome and enter a whole-dollar wager. Cash is deducted when the wager is accepted. The displayed percentages show the current split of the pool. Refresh gets the latest pool and status.
- Markets stop accepting wagers at the deadline or when staff select **Close now**. Staff select and confirm the winner after close. Staff can also refund an unsettled market.
- Winners receive a proportion of the entire pot based on their share of the winning side. For example, a $20 winning stake out of $80 on that side earns $50 from a $200 pool, including the original stake. Payouts are rounded to cents while distributing the entire pool. There is no house fee. If the winning side has no wagers, all stakes are refunded.
- Players collect payouts and refunds from **Results & claims**, including after reconnecting or restarting the resource. The resource keeps unclaimed cash available to its original character.

## Persistence and cash review

Market state uses server resource KVP. Include the server's resource KVP database and VORP database in your backups. Older fully paid markets are pruned as new markets are published.

VORP cash writes and the resource ledger use separate storage. The resource records a cash operation before calling VORP and checks the live character balance afterward. An interrupted or unverified payment can appear in **Manage markets** as a cash review. Verify the character's cash movement against your server logs and cash records before marking it applied or unapplied. The review records the result in the ledger without moving cash again. A full server crash can also occur after a live balance change and before VORP saves that balance. Reconcile VORP cash and the ledger after an unclean shutdown if your records show a discrepancy.

## Verification

The Lua files were parsed with Lua 5.4 and the JavaScript was syntax-checked. A mocked VORP run covered staff permissions, invalid wagers, cash debit, market closing, pool settlement and rounding, ledger reload, duplicate claim prevention, refunds, and pending cash review. Live RedM and the installed VORP version were unavailable for integration testing. Before rollout, exercise a small wager and payout in your staging server, then reconnect and verify the saved cash balance.

References:
- VORP Core inventory cash calls: https://github.com/VORPCORE/vorp_inventory-v2
- Cfx Lua NUI callbacks: https://docs.fivem.net/docs/scripting-reference/runtimes/lua/functions/RegisterNUICallback/
