Add animation assets (Animation or KeyframeSequence) under these folders using Roblox Studio.

Naming conventions (follow these exact folder names so AnimationLoader.LoadTrack finds them):
- Slide
- SlideJump
- Landing
- Front Roll
- Back Roll
- Left Roll
- Right Roll

Preferred structure per folder:
- [FolderName]/Humanoid/AnimSaves/[AssetName] (recommended)
- or [FolderName]/AnimSaves/[AssetName]
- or [FolderName]/[Animation]

Notes:
- AnimationLoader searches `ReplicatedStorage.animations`.
- Add real Animation instances in Studio and then export via Rojo if you want them tracked in Git.
- If an animation is missing the code will fall back to a generic animation; add the named assets for best visual fidelity.