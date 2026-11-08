class_name Layers
extends RefCounted
## Physics layer bit masks.

## Walls and other static world bodies.
const WORLD: int = 1
## Every character. The character scene uses this layer.
const CHARACTER: int = 2
## Every [Sandal]. The character pickup area scans this layer.
const SANDAL: int = 4
