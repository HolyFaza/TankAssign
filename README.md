# TankAssign v1.0.1.

Tank assignment addon for **WoW 1.12.1 / Turtle WoW**.

---

## Installation

1. Copy the `TankAssign` folder to `Interface/AddOns/`
2. Required folder structure:

```
Interface/AddOns/TankAssign/
├── TankAssign.lua
├── TankAssign.toc
├── TankAssign.xml
├── BossData.lua
├── TankAssign_icon.tga
├── TankAssign_target.tga
├── README.md
├── Sounds/
│   └── bucket.wav
└── textures/
    ├── mark_1_star.tga ... mark_8_skull.tga
```

---

## Commands

| Command | Description |
|---|---|
| `/ta` | Toggle main editor (RL/Assist only) |
| `/ta sync` | Broadcast template to raid |
| `/ta assign` | Toggle personal assignment window |
| `/ta panel` | Toggle combat marker panel |
| `/ta fw` | Toggle Fear Ward queue manager |
| `/ta options` | Open options |
| `/ta help` | List all commands |

---

## Features

### Minimap Button
- **LMB** — open main editor (RL/Assist only)
- **RMB** — open options
- **Drag** — reposition

### Combat Marker Panel
- 8 raid marker buttons
- **LMB** on marker — tank assignment dropdown
- **RMB** on marker — CC assignment dropdown
- **Target button** (crosshair) — assign Boss/Add or Custom text target to a tank
- **Presets** — ⚠️ Work in progress

### Tank Assignment
- Assign tanks to raid markers
- Multiple marks per tank supported
- Existing mark assignments shown as icons in dropdown

### CC Assignment
- Two-level dropdown: spell → player list
- Assigned player shown in green `[X]`
- Supports: Polymorph, Banish, Shackle Undead, Hibernate, Entangling Roots

### Target Button
- **Boss / Adds** — from BossData.lua, filtered to current zone
- **Custom** — Right/Left side, N/S/E/W + user-defined targets (Options)

### Personal Window
- **Tanks**: target → FW queue → CC → own taunt CDs → other AoE taunts
- **Priests**: FW assignment, queue position, CD, cast button
- **CC players**: assigned spell and target
- **Viewers (V)**: all assignments → CC → AoE taunts

### Fear Ward Queue
- Up to 2 tanks, each with independent priest queue
- Each priest in one queue only
- CD display (READY / Ns), alert banner on your turn
- Two-click cast: first targets tank, second casts

### Taunt Cooldown Tracking

| Class | Spell | CD | AoE |
|---|---|---|---|
| Warrior | Taunt | 8s | |
| Warrior | Mocking Blow | 2 min | |
| Warrior | Challenging Shout | 10 min | ✓ |
| Druid | Growl | 10s | |
| Druid | Challenging Roar | 10 min | ✓ |
| Paladin | Hand of Reckoning | 10s | |
| Shaman | Earthshaker Slam | 10s | |

### Death Alert
- Red banner + sound on tank death
- Unattended target shown in all tanks' windows
- Clears on res or after 15s

### Options
- Font size, window opacity
- Show outside raid / Hide in BG (WSG, AB, AV, Sunnyglade Valley)
- Custom assignment targets

---

## Notes

- **Earthshaker Slam** and **Hand of Reckoning** are Turtle WoW custom abilities
- **Presets** require SuperWoW for reliable multi-mob support — currently WIP
- Only communicates with other TankAssign clients (prefix: `TankAssign`)
