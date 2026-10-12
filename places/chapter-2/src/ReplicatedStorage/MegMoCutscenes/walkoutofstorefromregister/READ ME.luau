--[[
READ ME - MegMo Animator Cutscene Package

This ModuleScript is only here as an instruction file.
It does not run unless another script requires it.

1. Find Your Export
   - Open ReplicatedStorage > MegMoCutscenes > walkoutofstorefromregister.
   - Keep every item in this folder together.
   - If a script warns that MegMoCutscenes is missing, the exported folder is not in ReplicatedStorage.

2. Recommended Setup
   - Move PlayServerTriggerExample into ServerScriptService and make sure it is enabled.
   - Move PlayClientReceiver into StarterPlayerScripts and make sure it is enabled.
   - Keep this cutscene folder inside ReplicatedStorage > MegMoCutscenes.

3. Trigger Setup
   - Set CutsceneSettings > Trigger to Manual, PartTouched, ProximityPrompt, Timed, or AutoStart.
   - If Trigger is PartTouched, set CutsceneSettings > TriggerPartPath to the part that starts the cutscene.
     Example: Workspace.CutsceneTrigger
   - If Trigger is ProximityPrompt, set CutsceneSettings > TriggerPromptPath to the prompt or an object containing it.
     Example: Workspace.NPC.StartCutscenePrompt
   - If the part is inside folders, use the full path.
     Example: Workspace.Map.CutsceneTriggers.IntroTrigger
   - Set CutsceneSettings > Playback to LocalPlayer or Everyone.
   - LocalPlayer plays for the player who touched the trigger.
   - Everyone plays for all players in the server.
   - You can change TriggerPartPath, TriggerPromptPath, Playback, Replay, DelaySeconds, AllowSkip, FadeInSeconds, FadeOutSeconds, and RestoreCamera without editing code.
   - To teleport after playback, set AfterCutsceneAction to Teleport and set TeleportPlaceId to the destination place's numeric ID.
   - LocalPlayer playback teleports the triggering player. Everyone playback teleports the players who watched the cutscene.
   - Teleporting requires PlayServerTriggerExample to run on the server. Roblox does not run teleports during Studio playtests; publish and test in the Roblox app.

4. Use The Player Instead Of The Dummy
   - Set CutsceneSettings > RigTargetMode to TriggeringPlayerClone.
   - The dummy rig is used as the animation template.
   - The cutscene creates a temporary clone of the triggering player's avatar.
   - The clone plays the cutscene, then is removed.
   - The dummy rig and player avatar should use the same rig type, for example both R15 or both R6.
   - Set CutsceneSettings > PlayerEndMode to ReturnToStart or MoveToCutsceneEnd.
   - ReturnToStart keeps the real player where they started.
   - MoveToCutsceneEnd moves the real player to the final dummy rig position.

5. Simple Local Preview
   - PlayLocalExample is only a quick local preview.
   - For full rig cutscenes, use the Recommended Setup above.

6. Use It From Your Own Script
   local ReplicatedStorage = game:GetService("ReplicatedStorage")
   local folder = ReplicatedStorage:WaitForChild("MegMoCutscenes"):WaitForChild("walkoutofstorefromregister")
   local data = require(folder:WaitForChild("CutsceneData"))
   local player = require(folder:WaitForChild("MegMoCutscenePlayer"))

   player.Play(data, {
       restoreCamera = true,
   })

   -- Optional: listen for MegMo Event tracks.
   -- The event payload is marker data; put your script action inside this callback.
   player.BindEvent("DoorOpen", function(payload, info)
       print("DoorOpen event fired at frame", info.frame, "payload:", payload)
       -- Example: open a door, emit particles, enable UI, or run your own gameplay code here.
   end)

7. Before Publishing Your Game
   - Open the RigAnimations folder.
   - Upload each KeyframeSequence as a Roblox Animation.
   - Paste each uploaded Animation ID into the Value property of the matching StringValue in RigAnimationIds.
   - Do not paste the ID into the Instructions attribute.
   - Studio can preview temporary KeyframeSequences, but published games need real uploaded Animation IDs.

8. Useful Notes
   - CutsceneData loads the exported timeline from CutsceneDataChunks.
   - Do not delete CutsceneDataChunks.
   - Sound, camera, face, particle, lighting, object property, event, and screen effect playback are included in this package.
   - Screen effects, faces, particles, lighting, and custom event callbacks run locally, so PlayClientReceiver must be in StarterPlayerScripts.
   - Generic Event tracks fire through MegMoCutscenePlayer.OnEvent, MegMoCutscenePlayer.BindEvent(name, callback), and matching BindableEvents inside CutsceneEvents.
   - Event payload text is exported as data and passed to callbacks. It is not executed as Lua automatically.
   - Generated files are safe to edit after export, but exporting again will replace this cutscene folder.

9. Help And Feedback
   - Roblox Group: https://www.roblox.com/communities/453627593/MegMo-Animator#!/about
   - Tutorials: The Meg and Mo Show
   - When reporting a bug, include your MegMo Animator build number and any Studio Output errors.
]]

return "MegMo Animator cutscene instructions. Open this ModuleScript and read the comments at the top."
