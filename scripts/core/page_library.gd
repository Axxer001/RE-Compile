extends RefCounted
# The five MVP Grimoire pages built in code (GDD §5, Tech Spec §3.2) until the
# PageDatabase's data/pages/<id>.tres files land (P5). Only AbilityPage fields
# are set, so the swap is a load() per page. Ability-specific constants that
# have no AbilityPage field (orbit radius and speed, teleport distance, buff
# sizes) live with the code that runs them.

const AbilityPage = preload("res://scripts/core/ability_page.gd")
const IDS := ["scorch_and_burn", "cultivate", "ring_of_fire", "quick_step", "sage_arts", "dragons_breath", "firefly", "explosion"]
const CodeAssembly = preload("res://scripts/core/code_assembly.gd")
# Teaching content [Sir, 2026-11-14: C++, one beginner lesson per page, in
# course order; original text]: [lesson, Grimoire tip, chant concept tags].
const LESSONS := ["C++ Intro", "C++ Get Started", "C++ Syntax", "C++ Output", "C++ Comments", "C++ Variables", "C++ User Input", "C++ Data Types"]
const TEACH := {
	"scorch_and_burn": ["C++ Intro: every C++ program is built the same way. #include <iostream> brings in the input/output library, int main() { ... } holds the code that runs, and return 0; tells the system the program finished without errors.",
		"Read a program from the top: the #include line first, then main. Nothing outside main runs on its own.",
		["include", "main", "return"]],
	"cultivate": ["C++ Get Started: you write C++ in a .cpp file, a compiler turns it into a program, and running it starts at the first line inside main(). The statements in main run one after another, top to bottom.",
		"Order matters: the second cout prints after the first. To make something happen first, put it first in main.",
		["compile", "main", "order"]],
	"ring_of_fire": ["C++ Syntax: each statement ends with a semicolon, and curly braces { } group statements into a block. using namespace std; lets you write cout instead of std::cout.",
		"Every { needs its matching }. A missing ; is the most common beginner error: the compiler reports it on the next line.",
		["semicolon", "braces", "namespace"]],
	"quick_step": ["C++ Output: cout << sends text to the screen. You can chain several << pieces in one statement, and end a line with endl or by putting \\n inside the text.",
		"cout does not add line breaks on its own: two couts without endl or \\n print on the same line.",
		["cout", "chaining", "endl"]],
	"sage_arts": ["C++ Comments: notes for people that the compiler ignores. // comments out the rest of a line; /* ... */ comments out everything between the markers, even across several lines.",
		"Commenting a line out is a safe way to switch it off without deleting it. A /* must always be closed by */.",
		["line_comment", "block_comment"]],
	"dragons_breath": ["C++ Variables: a variable is a named box for a value. Declare it with a type and a name, then give it a value with =, like int ticks = 10;. const makes a value that can never change.",
		"A variable must be declared before it is used, and its name may not start with a digit or be a C++ keyword.",
		["declare", "assign", "const"]],
	"firefly": ["C++ User Input: cin >> reads what the user types and stores it in a variable. The variable must already be declared, and its type decides what cin will accept.",
		"cin stops reading a word at the first space. Prompt first with cout so the user knows what to type.",
		["cin", "extract", "prompt"]],
	"explosion": ["C++ Data Types: every variable has a type. int holds whole numbers, float and double hold decimals (double more precisely), bool holds true or false, char holds one character in single quotes, string holds text in double quotes, and auto lets the compiler pick the type from the value.",
		"Pick the smallest type that fits the value: whole counts are int, measurements are double, yes/no flags are bool.",
		["int", "double", "bool", "char", "string", "auto"]],
}

static func make(id: String) -> Resource:
	var p: Resource = AbilityPage.new()
	p.id = StringName(id)
	match id:
		"scorch_and_burn":
			p.title = "Scorch and Burn"
			p.kind = AbilityPage.Kind.ATTACK
			p.description = "Launch a medium-sized fireball. On contact with an enemy or obstacle, it explodes dealing AOE damage in a small radius."
			p.special_description = "Launch a massive fireball at a targeted area. On impact, it detonates dealing large AOE damage to all enemies within the blast zone."
			p.damage_pct = 0.10
			p.effect_id = "Burn"
			p.effect_s = 5.0
			p.special_damage_pct = 0.50
			p.special_cooldown_s = 15.0
			p.special_effect_s = 10.0
			p.mastery_applies = true # the special's cooldown
		"cultivate":
			p.title = "Cultivate"
			p.kind = AbilityPage.Kind.SKILL
			p.description = "Channel inner focus. For 10 seconds, the player gains increased Magic Power, Spell Mastery, and Attack Speed."
			p.cooldown_s = 20.0
			p.duration_s = 10.0
		"ring_of_fire":
			p.title = "Ring of Fire"
			p.kind = AbilityPage.Kind.SPELL
			p.description = "Summon 6 fireballs that orbit the player in a ring. The fireballs persist for 10 seconds, dealing damage and Scorched Slow to any enemy they touch."
			p.rank_req = "D"
			p.mp_cost = 30.0
			p.cooldown_s = 15.0
			p.mastery_applies = true
			p.damage_pct = 0.15
			p.duration_s = 10.0
		"quick_step":
			p.title = "Quick Step"
			p.kind = AbilityPage.Kind.SKILL
			p.description = "Instantly teleport 5 meters in the direction of the currently held movement key. If no movement key is held, the player teleports forward."
			p.cooldown_s = 10.0
		"dragons_breath":
			p.title = "Dragon's Breath"
			p.kind = AbilityPage.Kind.SPELL
			p.description = "Breathe a continuous torrent of flame for 10 seconds, scorching every enemy caught in the blaze. While breathing, you cannot use other attacks, skills or spells."
			p.mp_cost = 50.0
			p.cooldown_s = 20.0
			p.mastery_applies = true
			p.damage_pct = 0.02 # per tick, every 0.5 s for 10 s (20 ticks, 40% in all) [Sir, 2026-11-14]
			p.effect_id = "Burn"
			p.effect_s = 5.0
			p.duration_s = 10.0
		"firefly":
			p.title = "Firefly"
			p.kind = AbilityPage.Kind.SPELL
			p.description = "Lock on to up to 5 enemies in sight and launch 30 tiny missiles into the sky, which split and rain down on the locked targets."
			p.mp_cost = 70.0
			p.cooldown_s = 15.0
			p.mastery_applies = true
			p.damage_pct = 0.30 # per missile
			p.effect_id = "Burn"
			p.effect_s = 5.0
		"explosion":
			p.title = "Explosion"
			p.kind = AbilityPage.Kind.SPELL
			p.description = "Aim at a distant area and channel for 20 seconds. Once fully charged, the locked area erupts in a cataclysmic explosion. While charging you cannot move, look around or use abilities, and taking damage breaks the spell."
			p.mp_cost = 0.0 # needs full MP and spends all of it (spell_service)
			p.cooldown_s = 300.0
			p.mastery_applies = true
			p.damage_pct = 10.0
			p.effect_id = "Burn"
			p.effect_s = 5.0
			p.duration_s = 20.0 # the charge
		"sage_arts":
			p.title = "Sage Arts"
			p.kind = AbilityPage.Kind.PASSIVE
			p.description = "When out of combat, the player passively regenerates HP and MP over time."
			p.rank_req = "D"
		_:
			return null
	p.lesson = TEACH[id][0]
	p.hints = TEACH[id][1]
	p.concepts = PackedStringArray(TEACH[id][2])
	p.code_lines = PackedStringArray(CodeAssembly.shown(id).get("lines", [])) # the Tech Spec block (variant 0)
	return p
