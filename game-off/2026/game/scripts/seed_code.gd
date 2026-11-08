class_name SeedCode
extends RefCounted
## Short share code of a tower seed, such as HS-4F2K9A. Six characters of a 32-letter alphabet hold 30 bits, so the code maps back to the seed.

## Prefix of every code.
const PREFIX: String = "HS-"
## Characters of a code after the prefix.
const LENGTH: int = 6
## Largest seed a code holds. Fresh seeds stay at or below it.
const MAX_SEED: int = (1 << 30) - 1
## Code alphabet without I, L, O and U, so a read-out code stays unambiguous.
const ALPHABET: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


## Returns the code of [param seed_value], which must lie in 1 to [constant MAX_SEED].
static func encode(seed_value: int) -> String:
	var code: String = ""
	var rest: int = clampi(seed_value, 0, MAX_SEED)
	for i: int in LENGTH:
		code = ALPHABET[rest & 31] + code
		rest >>= 5
	return PREFIX + code


## Returns the seed of [param code], or 0 when the code is not valid. The prefix and case are optional, and O, I and L read as 0, 1 and 1.
static func decode(code: String) -> int:
	var text: String = code.strip_edges().to_upper()
	if text.begins_with(PREFIX):
		text = text.substr(PREFIX.length())
	if text.length() != LENGTH:
		return 0
	var value: int = 0
	for i: int in LENGTH:
		var letter: String = text[i]
		if letter == "O":
			letter = "0"
		elif letter == "I" or letter == "L":
			letter = "1"
		var digit: int = ALPHABET.find(letter)
		if digit < 0:
			return 0
		value = (value << 5) | digit
	return value


## Returns the seed in the [code]seed[/code] key of a URL [param query] such as [code]?seed=HS-4F2K9A[/code], or 0 when it is missing or invalid.
static func from_query(query: String) -> int:
	var text: String = query.trim_prefix("?")
	for pair: String in text.split("&", false):
		if pair.get_slice("=", 0) == "seed":
			return decode(pair.get_slice("=", 1).uri_decode())
	return 0
