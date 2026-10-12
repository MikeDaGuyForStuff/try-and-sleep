# Try and Sleep

Source code for the **Try and Sleep** Roblox experience, synced with [Rojo](https://github.com/rojo-rbx/rojo) 7.7.1.

The experience has three places. Each one has its own Rojo project file and port, so you can sync all three at once in separate Studio windows. Each project only connects to its own place ID, so you can't sync one place's scripts into another by mistake.

| Place | Place ID | Project file | Scripts | Port |
|---|---|---|---|---|
| try and sleep (lobby, start place) | 138291067500808 | `default.project.json` | `src/` | 34872 |
| try and sleep chapter 1 | 88451914043309 | `chapter-1.project.json` | `places/chapter-1/src/` | 34873 |
| try and sleep chapter 2 | 140272202634570 | `chapter-2.project.json` | `places/chapter-2/src/` | 34874 |

Only scripts live in this repo. Maps, models, sounds, RemoteEvents, and cutscene animation data stay in the places on Roblox. The chapter projects map each script one by one, so Rojo never touches the other instances around them.

## Getting started

Install the toolchain (Rojo is pinned in `rokit.toml`):

```bash
rokit install
```

Open the place in Roblox Studio, then start the Rojo server for it:

```bash
rojo serve                         # lobby
rojo serve chapter-1.project.json  # chapter 1
rojo serve chapter-2.project.json  # chapter 2
```

In the Studio Rojo plugin, connect to `localhost` on that place's port.

### Adding a script to a chapter

Create the file under that chapter's `places/<chapter>/src/` folder, then add an entry for it in the chapter's `.project.json`. Name the file by script type:

- `Name.server.luau`: Script
- `Name.client.luau`: LocalScript
- `Name.luau`: ModuleScript

## Credits

The cutscene system in chapter 2 (`MegMoCutscenes`) was exported from [MegMo Animator](https://www.roblox.com/communities/453627593/MegMo-Animator#!/about).

## Secrets

Never commit API keys, webhook URLs, or cookies. Put them in a `Secrets.luau` module or a `.env` file, which `.gitignore` excludes, or better, in Roblox's Secrets Store (`HttpService:GetSecret`).
