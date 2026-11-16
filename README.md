# Miroga Utilities

Personal WoW Forever addon with three modules. `/mu` opens the panel.

- **Powershift**: bind `Powershift: Cat Form` and `Powershift: Bear Form` under Key Bindings > AddOns. Key press cancels the form, key release casts it.
- **CombatText**: `/mu text`. Based on ClearCombatText by Booyaka101 (MIT, see `Modules/CombatText/LICENSE`).
- **FlagPlates**: `/mu flag`, `/mu target`.
- **Home**: `/mu` opens on the module switches; an off module does not start after the next reload.
- **LayerSwap host**: Host off after login (at your first click), unless you turned it on yourself last session. LayerSwap's own 4 min after a swap stay untouched.
- **Naowh tweaks**: scrolls and buff drinks only in dungeons and raids; `/rxp hide` also hides Naowh's RXP guide window.
- **Update merge**: `/mu u`. When NaowhUI is newer than your profiles, a popup takes one snapshot of your EllesmereUI and Naowh Forever profiles and opens NaowhUI. After the import and a reload, every changed setting shows OLD (before) and NEW (after); you click the side you want. Only the list of settings you kept on OLD stays saved.

A module stays off while its standalone addon (`KPCombatText`, `KPFlagPlates`) is enabled.
