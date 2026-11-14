extends RefCounted
# The five MVP Grimoire pages built in code (GDD §5, Tech Spec §3.2) until the
# PageDatabase's data/pages/<id>.tres files land (P5). Only AbilityPage fields
# are set, so the swap is a load() per page. Ability-specific constants that
# have no AbilityPage field (orbit radius and speed, teleport distance, buff
# sizes) live with the code that runs them.

const AbilityPage = preload("res://scripts/core/ability_page.gd")
const IDS := ["scorch_and_burn", "cultivate", "ring_of_fire", "quick_step", "sage_arts", "dragons_breath", "firefly", "explosion",
	"flight_of_the_phoenix", "call_of_the_phoenix", "rise_of_the_phoenix", "heads_or_tails", "where_are_my_coins", "let_it_ride", "all_in"]
const CodeAssembly = preload("res://scripts/core/code_assembly.gd")
# Teaching content [Sir, 2026-11-14: C++, one beginner lesson per page, in
# course order; original text]: [lesson, Grimoire tip, chant concept tags].
const LESSONS := ["C++ Intro", "C++ Get Started", "C++ Syntax", "C++ Output", "C++ Comments", "C++ Variables", "C++ User Input", "C++ Data Types",
	"C++ Operators", "C++ Strings", "C++ Math", "C++ Booleans", "C++ If...Else", "C++ Switch", "C++ While Loop"]
const TEACH := {
	"scorch_and_burn": ["C++ Intro: every C++ program, from a tiny test to a whole game, is built on the same skeleton. Scorch and Burn is the simplest spell, so it shows that skeleton bare.\n\nIn this incantation:\n• `#include <iostream>` loads the input/output library. Without it, the program has no way to speak.\n• `int main() { ... }` is the entry point. The computer starts reading here, and only here.\n• `cout << \"...\";` is the spell's one action. It sends the fireball's line to the screen.\n• `return 0;` ends main and reports success. 0 means everything went fine.\n\nThe curly braces { } mark where main begins and ends. Every line of the spell lives between them. (The using line is explained on Ring of Fire's page.)",
		"Read a program from the top: the #include line first, then main. Nothing outside main runs on its own.",
		["include", "main", "return"]],
	"cultivate": ["C++ Get Started: you write C++ in a .cpp file. A compiler checks it and turns it into a program the computer can run. When it runs, it starts at the first line inside main() and works down, one statement at a time.\n\nCultivate shows that order:\n• The first cout prints \"Cultivate: focus gathers.\"\n• The second cout runs only after the first is done: \"Power, mastery and speed rise.\"\n• `return 0;` runs last and closes the program.\n\nSwap the two cout lines and the messages swap too. In C++, the order you write is the order things happen. That is why the lines must be arranged correctly in Code Assembly. (Both messages print on one line; Quick Step's page shows how to break lines.)",
		"Order matters: the second cout prints after the first. To make something happen first, put it first in main.",
		["compile", "main", "order"]],
	"ring_of_fire": ["C++ Syntax: syntax is the grammar of C++. Break it and the compiler refuses to build your program.\n\nThree rules hold this ring together:\n• Every statement ends with a semicolon `;`. It is the full stop of C++, and each cout line ends with one.\n• Curly braces `{ }` group statements into a block. main's block holds both of the ring's lines.\n• `using namespace std;` lets you write cout instead of `std::cout`. Both name the same tool from std, the standard library.\n\nSpaces and line breaks mostly don't matter to the compiler. Semicolons and braces do. Forget one ; and the compiler reports an error, often on the line after the mistake.",
		"Every { needs its matching }. A missing ; is the most common beginner error: the compiler reports it on the next line.",
		["semicolon", "braces", "namespace"]],
	"quick_step": ["C++ Output: cout (say \"see-out\") writes to the screen. The << arrows push each piece into it, left to right.\n\nQuick Step uses two tools:\n• `cout << \"Quick Step!\"` sends the text in quotes to the screen.\n• `<< endl` ends the line, so the next output starts on a fresh one.\n\nYou can chain as many << pieces as you like in one statement. Writing `\\n` inside the text also starts a new line. Without `endl` or `\\n`, both of Quick Step's lines would run together, just like Cultivate's do.",
		"cout does not add line breaks on its own: two couts without endl or \\n print on the same line.",
		["cout", "chaining", "endl"]],
	"sage_arts": ["C++ Comments: a comment is a note for people. The compiler skips it completely, so it never changes what the program does.\n\nIn this incantation:\n• `//` starts a line comment. Everything after it, to the end of the line, is ignored. Sage Arts uses one to say when it works: out of combat.\n• `/*` starts a block comment and `*/` ends it. Everything between them is ignored, even across several lines.\n\nGood comments explain why code exists. They also switch a line off without deleting it: put `//` in front of it, and that line stops running.",
		"Commenting a line out is a safe way to switch it off without deleting it. A /* must always be closed by */.",
		["line_comment", "block_comment"]],
	"dragons_breath": ["C++ Variables: a variable is a named box that holds a value. You create one by giving a type, a name and, usually, a starting value.\n\nDragon's Breath keeps its numbers in two boxes:\n• `int ticks = 20;` makes a whole-number box called ticks, holding 20: the breath's 20 hits.\n• `double power = 0.02;` makes a decimal box called power, holding 0.02: 2% of Magic Pow per hit.\n• `cout << \"Breath ticks: \" << ticks` prints the label, then the value inside ticks, not the word \"ticks\".\n\nHere = means \"store this\", not \"is equal to\". A name may use letters, digits and _, but can't start with a digit. Put const in front, as in `const int SECONDS = 10;`, and the value can never change.",
		"A variable must be declared before it is used, and its name may not start with a digit or be a C++ keyword.",
		["declare", "assign", "const"]],
	"firefly": ["C++ User Input: cin (say \"see-in\") reads what the user types. The >> arrows point from the keyboard into a variable.\n\nFirefly asks how many enemies it has locked:\n• `int targets;` makes an empty whole-number box. cin needs a box ready to fill.\n• `cout << \"How many targets? \";` asks first, so the user knows what to type.\n• `cin >> targets;` waits for a number and stores it in targets.\n• `30 / targets` splits the 30 missiles: 2 targets get 15 each.\n\nThe box's type decides what cin accepts: an int takes whole numbers only. cin also stops reading at the first space, so it reads one word or number at a time.",
		"cin stops reading a word at the first space. Prompt first with cout so the user knows what to type.",
		["cin", "extract", "prompt"]],
	"explosion": ["C++ Data Types: every variable has a type. The type decides what the box can hold and how much memory it takes.\n\nExplosion's numbers each need a different type:\n• `int damage = 1000;` holds a whole number: the 1000% blast.\n• `double radius = 25.0;` holds a decimal: the 25 m radius. A double keeps about 15 digits; a float about 7.\n• `bool charged = true;` holds only true or false: is the charge complete? cout prints true as 1 and false as 0.\n\nTwo more types: char holds one character in single quotes, like `'E'`, and string holds text in double quotes. auto lets the compiler pick the type from the value you give.",
		"Pick the smallest type that fits the value: whole counts are int, measurements are double, yes/no flags are bool.",
		["int", "double", "bool", "char", "string", "auto"]],
	"flight_of_the_phoenix": ["C++ Operators: operators are the symbols that do maths and change values. `+ - * /` add, subtract, multiply and divide. `%` gives the remainder of a division.\n\nFlight of the Phoenix works out its own numbers:\n• `climb / seconds` divides the 30 m climb by its 5 seconds: 6 metres every second.\n• `100 * 5` multiplies: at the top of the climb the dive hits for 500%.\n• `mp -= 80;` is a shortcut for `mp = mp - 80;`: the spell's cost taken from your MP. `+=`, `*=` and `/=` work the same way.\n• `kills++;` adds exactly one. `--` takes one away.\n\nDividing two `int` values throws away the remainder: `7 / 2` is 3, and `7 % 2` is the 1 that was left. Use a `double` when you need the decimals.",
		"Operators follow maths order: * and / before + and -. Brackets go first, so (t - 2) / 3 subtracts before it divides.",
		["arithmetic", "remainder", "compound_assign", "increment"]],
	"call_of_the_phoenix": ["C++ Strings: a `string` holds text, like a spell's name. It needs `#include <string>` at the top, and its text goes in double quotes.\n\nCall of the Phoenix announces itself in text:\n• `string spell = \"Call of the Phoenix\";` stores the name in a string variable.\n• `spell.length()` asks the string how many characters it holds, spaces included.\n• `first + \" \" + second` joins strings end to end. Here + means \"stick together\", not \"add\".\n• `call += \" of the Phoenix\";` adds more text onto the end of `call`.\n\nA string is always in double quotes; a single character in single quotes is a `char`. You can join a string to text in quotes, but not straight to a number: print numbers with << instead.",
		"length() counts every character, spaces too: \"Fire rain\" is 9 long.",
		["string", "length", "concatenate"]],
	"rise_of_the_phoenix": ["C++ Math: `#include <cmath>` brings in a toolbox of maths functions. You call one by its name, with the values it needs in brackets.\n\nRise of the Phoenix counts its way to rebirth:\n• `min(kills, 20)` gives the smaller of two values, so the counter never shows more than 20/20.\n• `max(hp, 100.0)` gives the larger: the phoenix rises with at least full health.\n• `sqrt(400)` is the square root, 20: the blast's knockback reach.\n• `pow(2, 5)` is 2 to the power of 5: 32.\n• `round(heal)` rounds to the nearest whole number: 2.4 becomes 2.\n\nA function call like `sqrt(x)` gives back a value, so you can print it, store it, or put it inside another call: `sqrt(pow(x, 2) + pow(y, 2))` is the distance between two points.",
		"Mixing int and double in max or min fails: write max(hp, 100.0), not max(hp, 100), when hp is a double.",
		["cmath", "min_max", "sqrt_pow", "round"]],
	"heads_or_tails": ["C++ Booleans: a `bool` holds one of two values, `true` or `false`, just like a coin has two faces. Programs use bools to answer yes-or-no questions.\n\nHeads or Tails flips its answers:\n• `bool heads = true;` stores a yes: this flip came up heads.\n• `(target <= range)` is a comparison. It asks a question and gives back a bool: is the target inside the 30 m range?\n• `==` asks \"is equal to\" and `!=` asks \"is not equal to\". `<`, `>`, `<=` and `>=` compare sizes.\n• `cout` prints true as 1 and false as 0. Put `boolalpha` in front and it prints the words true and false instead.\n\nDon't mix up `=` and `==`: one equals sign stores a value, two ask a question.",
		"A comparison is itself a bool: (bounces > 3) is false until the fourth bounce. Brackets keep it apart from the << arrows.",
		["bool", "true_false", "comparison", "boolalpha"]],
	"where_are_my_coins": ["C++ If...Else: `if` lets a program choose. It checks a condition, and only when the condition is true does it run the block in `{ }` that follows.\n\nWhere are my Coins? decides when to spend:\n• `if (coins == 10) { ... }` runs its block only with a full pocket of 10 coins.\n• `else { ... }` runs when the condition is false: keep collecting.\n• `else if (slow > 0)` checks a second condition only when the first one failed, so exactly one branch runs.\n• `&&` means \"and\": `coins == 10 && buffed` needs both to be true. `||` means \"or\", and `!` turns true into false.\n\nThe condition always sits in round brackets, and there is no semicolon after `if (...)`: a stray ; ends the if on the spot.",
		"Only one branch of an if / else if / else chain runs: the first whose condition is true, or else the last.",
		["if", "else", "else_if", "logic"]],
	"let_it_ride": ["C++ Switch: `switch` compares one value against a list of fixed cases and jumps to the one that matches. It reads like a dice table.\n\nLet it Ride rolls the die and looks the result up:\n• `switch (roll) { ... }` picks which case to run from the value of roll.\n• `case 6:` marks where the code for a 6 begins: the jackpot.\n• `break;` stops the switch. Without it, the code runs straight on into the next case, which is called falling through.\n• `default:` runs when no case matches, like an else.\n\nStacking cases with no code between them, as in `case 1: case 2: case 3:`, sends all three rolls to the same lines: a low roll. A case value must be a constant, such as 6 or 'H', never a variable.",
		"Forgetting break is the classic switch bug: the next case runs too. Put break at the end of every case unless you mean to fall through.",
		["switch", "case", "break", "default"]],
	"all_in": ["C++ While Loop: a `while` loop runs its block again and again, as long as its condition stays true. It checks the condition before every round.\n\nAll In counts down its gamble:\n• `while (seconds > 0) { ... }` keeps looping while time is left on the Invincibility.\n• `seconds--;` inside the block moves the loop toward its end. Something in the block must change the condition, or the loop never stops.\n• `do { ... } while (left > 0);` is the other form: it runs the block first and checks after, so it always runs at least once. Note the semicolon after its while.\n• `while (!buffed && tries < 3)` loops on a whole bool expression, so a loop can stop for more than one reason.\n\nA loop whose condition never turns false is an infinite loop: the program hangs. Before you write a loop, know what will end it.",
		"Every while loop needs a way out: change the variable in its condition inside the block (count down, count up, or set a bool).",
		["while", "do_while", "condition", "infinite_loop"]]
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
		"flight_of_the_phoenix":
			p.title = "Flight of the Phoenix"
			p.kind = AbilityPage.Kind.SPELL
			p.description = "Pull every enemy within 20 metres to you, then rise 30 metres into the sky on wings of flame. Choose a spot inside the burning ring and dive: the higher you climbed, the harder you land."
			p.mp_cost = 80.0
			p.cooldown_s = 60.0
			p.mastery_applies = true
			p.damage_pct = 1.0 # 100% until 2 s of climb, then up to 500% at the peak (spell_service)
			p.effect_id = "Burn"
			p.effect_s = 5.0
		"call_of_the_phoenix":
			p.title = "Call of the Phoenix"
			p.kind = AbilityPage.Kind.SPELL
			p.description = "Hold still and mark up to three areas on the ground. When the call ends, a phoenix's storm of fireballs rains down on every marked area."
			p.mp_cost = 50.0
			p.cooldown_s = 30.0
			p.mastery_applies = true
			p.damage_pct = 0.10 # each fireball is a basic Scorch and Burn fireball
			p.effect_id = "Burn"
			p.effect_s = 5.0
			p.duration_s = 5.0
		"rise_of_the_phoenix":
			p.title = "Rise of the Phoenix"
			p.kind = AbilityPage.Kind.PASSIVE
			p.description = "Every burning enemy you kill feeds the flame: +2% max HP and +2% max MP. After 20 kills the phoenix is ready: the next time you fall, you rise again in a burst of fire."
			p.damage_pct = 2.0 # the rebirth blast
			p.effect_id = "Burn"
			p.effect_s = 5.0
		"heads_or_tails":
			p.title = "Heads or Tails"
			p.kind = AbilityPage.Kind.ATTACK
			p.rank_req = "D"
			p.description = "Flick a spinning coin at a single enemy (30 m). An enemy holding Pocket Change passes the coin on: it bounces to another enemy with Pocket Change within 10 m, up to 3 times, hitting harder each bounce."
			p.special_description = "Throw a giant coin that bursts in a 20 m blast, leaving every enemy it catches with Pocket Change for 10 seconds."
			p.damage_pct = 0.80
			p.special_damage_pct = 1.20
			p.special_cooldown_s = 20.0
			p.special_effect_s = 10.0
			p.effect_id = "Pocket Change"
			p.effect_s = 10.0
			p.mastery_applies = true # the special's cooldown
		"where_are_my_coins":
			p.title = "Where are my Coins?"
			p.kind = AbilityPage.Kind.PASSIVE
			p.rank_req = "D"
			p.description = "Every kill drops a coin into your pocket, up to 10. With 10 coins, the moment you have any buff your pockets spill: every enemy within 30 m gets Heavy Pockets, slowed 80% and recovering over 10 seconds."
			p.effect_id = "Heavy Pockets"
			p.effect_s = 10.0
		"let_it_ride":
			p.title = "Let it Ride"
			p.kind = AbilityPage.Kind.SPELL
			p.rank_req = "D"
			p.description = "Roll the die. 1-3: lose every buff (next roll comes sooner). 4-5: Gambler's High. 6: the Jackpot. Roll low twice in a row and you're hooked: Gambling Addiction."
			p.mp_cost = 0.0
			p.cooldown_s = 5.0
			p.duration_s = 20.0 # Gambler's High (the Jackpot lasts 10 s)
		"all_in":
			p.title = "All In"
			p.kind = AbilityPage.Kind.SPELL
			p.rank_req = "D"
			p.description = "Sacrifice 99% of your current HP and become Invincible for 10 seconds. If any buff is active when the Invincibility ends, every lost HP returns and you gain 200% Magic Pow for 10 seconds; if not, -70% Mov Spd and Atk Spd for 5 seconds."
			p.mp_cost = 0.0
			p.cooldown_s = 60.0
			p.duration_s = 10.0
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
