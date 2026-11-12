# Coin Simulator (Roblox, Luau, Rojo)

A small coin-collecting game built over ten days as a learning project and portfolio piece. Players pick up coins, spend them in a shop, fight a training dummy with a sword, and compete in timed rounds. The server decides every coin, purchase, hit, and round result; the client only shows state and sends requests.

Status: runs in Roblox Studio (Play solo). The place has not been published, so DataStore saving and Robux purchases have never run against Roblox's live services. See [Known gaps](#known-gaps).

## Features

| Feature | How it works | Lesson |
|---|---|---|
| Coins | Five gold parts tagged `Koin`. Touching one pays 1 coin, hides it, and brings it back after 8 seconds. Any part tagged `Koin` in Studio becomes a coin. | [Day 1](docs/hari-01.md), [9](docs/hari-09.md), [10](docs/hari-10.md) |
| Shop | Three items at 5, 15 and 50 coins. The client sends an item id; the server looks up the price, checks the balance and ownership, and replies to that player only. | [Day 2](docs/hari-02.md), [3](docs/hari-03.md) |
| Saving | Coins, inventory and purchase receipts saved per `UserId` with a session lock, retries, autosave and a save on shutdown. | [Day 4](docs/hari-04.md) |
| Shop and HUD UI | Built from a client script. Mouse, touch, keyboard (B) and gamepad (Y; tested with simulated input only). Layout checked in six Device Simulator presets, from a 359 px wide phone to a 1080p console. | [Day 5](docs/hari-05.md) |
| Monetization | "2x Coins" game pass and "+100 Coins" developer product. Receipts are idempotent. IDs are 0 until the place is published. | [Day 6](docs/hari-06.md) |
| Rounds | Intermission 15 s, Round 45 s, Result 6 s. Coins collected during a round count as score; the top collectors get +10. Round state reaches clients through attributes, not remotes. | [Day 7](docs/hari-07.md) |
| Sword | Damages other players and a training dummy. A kill pays 5 coins. The server checks range, cooldown, target and whether the sword is equipped. | [Day 8](docs/hari-08.md) |
| Anti-exploit pass | One per-player rate limiter shared by the shop and sword remotes, per-player state cleared on leave, respawn-safe client connections. | [Day 9](docs/hari-09.md) |

## Architecture

Rojo maps three folders into the place (`default.project.json`):

```text
src/server  -> ServerScriptService.Server            (init.server.luau wires the modules below)
src/shared  -> ReplicatedStorage.Shared              (Config.luau, read by both sides)
src/client  -> StarterPlayer.StarterPlayerScripts.Client
```

| Module | Side | Responsibility |
|---|---|---|
| `Config` | shared | Every tunable number: prices, rewards, cooldowns, round lengths, rate limits, product IDs. Frozen. |
| `PlayerData` | server | Session per player: load, save, session lock, `addCoins`, `purchase`. The only place coins change. |
| `Store` | server | DataStore wrapper with an `UpdateAsync`-style interface, plus an in-memory backend for tests. |
| `Inventory` | server | Owned items as a plain set that can be saved as is. |
| `StatsMirror` | server | Copies server data into `leaderstats` and an `Inventory` folder for display. Never read for decisions. |
| `Shop` | server | `BuyItem` remote: rate limit, then validation, then `PlayerData:purchase`. |
| `CoinPickup` | server | Binds every `Koin`-tagged part, pays through `PlayerData`, hides and respawns coins. |
| `Rounds` | server | Round state machine; writes phase, end time and winners as attributes. |
| `Combat` | server | Gives the sword, spawns the dummy, validates `Attack` requests and applies damage. |
| `Monetization` | server | `ProcessReceipt` and game pass ownership, with injectable Roblox calls. |
| `RateLimit` | server | Token bucket per player, shared by `Shop` and `Combat`. |
| `init.client` | client | Reads the mirrored data, sends buy requests, shows replies. |
| `ShopView`, `RoundStatus` | client | Draw the HUD and shop from a view state; no data access, no remotes. |
| `Sword` | client | On swing, proposes the nearest target to the server. |

`src/shared/Hello.luau` is left over from the project template and nothing requires it.

A purchase travels: shop button, `BuyItem:FireServer(itemId)`, `RateLimit`, `Shop` checks, `PlayerData:purchase`, `StatsMirror` updates `leaderstats`, replication shows the new value, `BuyResult` tells the buyer what happened.

Modules take their dependencies (data store, clock, Roblox services) as arguments, so each one can be tested with fakes in an unpublished place.

## Security decisions

Each decision has a test that tries to break it. Results are in section 5 of the linked lesson.

| Decision | Test that tries to break it |
|---|---|
| Remotes carry intent only (item id, sword target), never a price, amount or damage. | Ten malformed calls, sent 1.1 s apart so each one passes the rate limit, including `nil`, `NaN`, a table, an Instance, a 10,000-character string, an unknown item, and `BuyItem("GoldCrown", 0)` with a fake price of 0: one reply, `NotEnoughCoins`, for the only real item id. ([Day 10](docs/hari-10.md)) |
| `leaderstats` is a mirror. Decisions read `PlayerData`. | The client sets its own coins to 999: purchase refused. The server overwrites the mirror with 999: purchase still refused, and the next pickup restores the real value. ([Day 10](docs/hari-10.md)) |
| Rate limit runs before any validation. | 50 `BuyItem` requests at once: 5 replies. 51 `Attack` requests: 2 hits. ([Day 9](docs/hari-09.md)) |
| Sword hits are measured from server positions: range 9 studs, 0.6 s cooldown, allowlisted targets. | `Attack` fired from 30 studs: no damage. From 5.1 studs: 25 damage. ([Day 8](docs/hari-08.md), [10](docs/hari-10.md)) |
| A collected coin is tracked in a server table, not by `CanTouch`. | The client re-enables a hidden coin on its side, then moves its own character in and out of it 10 times in 6 seconds: no coins. ([Day 10](docs/hari-10.md)) |
| Tags set by the client are ignored. | The client tags the Baseplate as a coin: nothing pays. ([Day 9](docs/hari-09.md)) |
| A failed load never saves defaults over real data, and never kicks the player. | 47 checks against a fake store: lock held by another server, lease expiry, retries, permanent errors. In Studio the player plays offline with a notice. ([Day 4](docs/hari-04.md)) |
| Developer product grants are idempotent. | The same `PurchaseId` delivered twice pays once; the receipt is saved before `PurchaseGranted` is returned. Fake receipts only. ([Day 6](docs/hari-06.md)) |

## Known gaps

- Teleport: character position is owned by the client. A modified client can move next to a target and land a hit about one second later (measured on Day 8). There is no server-side movement check yet; the options and why it was deferred are in [Day 9](docs/hari-09.md).
- Coin touches have no distance check, so a modified client could report touches from far away. Day 9, exercise 3 adds one.
- A player standing inside a coin is paid each time it reappears (once per 8 seconds).
- DataStore, game pass and developer product code has only run against fakes. Product and pass IDs are 0.
- `Config.Round.MinPlayers` is 1 so a round can be tested alone. Raise it to 2 before publishing.
- Every live test ran with one client. Two-player cases (PvP, two players on one coin) were tested with fake players in unit tests only.

## Running it

Requirements: Roblox Studio with the [Rojo plugin](https://rojo.space/docs/v7/getting-started/installation/), and [Rokit](https://github.com/rojo-rbx/rokit).

```bash
rokit install        # rojo 7.7.1, selene 0.32.0, StyLua 2.6.0 from rokit.toml
rojo serve           # serves default.project.json on port 34872
```

In Studio, open a new Baseplate place, connect the Rojo plugin, then press Play. The server script creates the coins, remotes, sword and training dummy. In the tested place, the template's SpawnLocation was the only object the repo does not define. To get a place file instead:

```bash
rojo build -o coin-simulator.rbxlx
```

The built file has a Baseplate but no SpawnLocation. It was built, not opened or played; every test ran through `rojo serve` in a Baseplate place.

Checks run before every commit:

```bash
selene src           # 0 errors, 0 warnings
stylua --check src
```

## How it was tested

- Unit tests ran inside Studio during Play through the Roblox Studio MCP server, against fresh module instances with a fake data store, a fake clock and fake players. From Day 6 on, suites were also run against deliberately broken versions of the code (mutants) to check that some test fails.
- Live tests used the real Studio test player: UI clicks, remote spam, malformed arguments, client-side tampering, respawns.
- On Day 10 every suite ran again in one Play session after the last code change: Day 3 36/36, Day 4 47/47, Day 5 55/55, Day 6 34/34, Day 7 19/19, Day 8 14/14, Day 9 12/12, Day 10 7/7 plus 2/2 timed. All 26 mutants from Days 7 to 10 were caught.
- The test scripts were run from outside this repository and are not committed. Each lesson lists its tests, mutants, and live results in section 5.

## Documentation

The lessons are in Indonesian, one per day: [docs/README.md](docs/README.md). Also: a [security review checklist](docs/keamanan-checklist.md) and a [demo video script](docs/rekam-demo.md).
