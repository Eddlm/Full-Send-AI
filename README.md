# Full Send AI
This script grabs the AI and does two main things:

- Faster laptimes, they:
   - Actively try to find the car's limit in each corner, and learn the track in the starting lap.
  - Slowly adjust their braking point per corner, such as they brake as late as possible without having to brake inside the corner. They also brake earlier if they overdo it.
- Safer battles, they:
  - Avoid other cars and keep parallels in a smoother and smarter way.
  - Lift if too close behind someone.
  - Also lift if someone further ahead is way too slow and in the racing line.
### Future Updates
- Human-like personalities, skills, and natural mistakes.
- Race tactics and more complex raceraft.
- QOL improvements the community asks for. There is probably some work to be done to improve Endurance or variable weather behavior.
## Installation / How to use
- **Though CM**: Drop the ZIP from releases onto the Content Manager from Custom Shader's patch. Go to Downloads (top right menu on CM), click Install.
- **Manual Installation**: Make a FullSendAI folder on ``(route to Assetto Corsa)\assettocorsa\apps\lua`` and drop the ZIP's contents inside.

Run the game once, this allows the script to install a configuration file for Content Manager. Then, you can navigate to Settings > Custom Shaders Patch > FULL SEND AI and have all the settings there.
  
## Compatibility
- NOT compatible with AI Whisperer, they will fight for control.
- Future releases may NOT be compatible with "New AI behavior" from CSP.

## ​How it works

### Cornering Speed
FSA divides the track in 50m sections and, for each, it keeps an eye on the AI's throttle. If its not 100% (full send), it checks the slip angle and increases the AI's percieved grip in that section, slowly, making it think it can go faster. The goal is either high slip (8º) or full throttle. If the AI suffers understeer, FSA will in turn reduce the percieved grip to reel them in.

### Braking distance
As the AI approaches a corner, FSA keeps an eye on brake input. The target is about 50% brake input in the last 500ms of corner approach. FSA adjusts the AI's percieved braking performance in such a way that AI will brake earlier or later, per corner, until they hit that "50% at 500ms" target.

### Avoidance and Overtaking
The hardest to work with. FSA tried to disable as much base systems as possible and implements smoother, smarter versions of them. AI will stay on the racing line until they encounter nearby AI. If they think they can overtake, they'll step out of the racing line. They will also lift to avoid rear ending others.
